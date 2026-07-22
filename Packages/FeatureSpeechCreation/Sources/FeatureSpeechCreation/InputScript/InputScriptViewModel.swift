//
//  InputScriptViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Observation
import ShuoCore

/// Owns the Input Script shell — title, purpose, and which mode is showing — and composes
/// one focused child view model per mode rather than accumulating a set of optional
/// properties for all three (CLAUDE.md §5, ARCHITECTURE.md §3.1.2).
@Observable
@MainActor
public final class InputScriptViewModel {
    public var title: String = ""
    public let purpose: SpeechPurpose
    public var mode: InputMode = .speak

    public let speakVM: SpeakModeViewModel
    public let writeVM: WriteModeViewModel
    public let attachVM: AttachFileModeViewModel

    /// Non-nil while the transcription step is on screen.
    ///
    /// The loading step lives here rather than on `CreateScriptCoordinator` on purpose:
    /// ARCHITECTURE.md §3.1.1 warns against reintroducing a full `Route`/`path` stack
    /// before it earns its keep, and one presented child covers what this flow actually
    /// needs today.
    public private(set) var loadingVM: LoadingRouteViewModel?

    /// Builds the draft handed to the analysis step once transcription has finished.
    ///
    /// The title falls back rather than being validated: reaching this point means the
    /// user recorded or wrote a whole speech, and blocking them at the last step over an
    /// empty text field would be a poor trade. They can rename it on the analysis screen.
    public func makeDraft(from transcript: Transcript) -> ScriptDraft {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScriptDraft(
            title: trimmedTitle.isEmpty ? Self.untitledTitle : trimmedTitle,
            purpose: purpose,
            transcript: transcript,
            recordingDuration: confirmedDuration
        )
    }

    /// How long the confirmed source runs, when that is knowable.
    ///
    /// Read from the confirmed mode only. Reading `speakVM` unconditionally — as this did
    /// once — meant a user who recorded, then switched to Write mode and typed instead,
    /// saved typed text stamped with the abandoned recording's duration. An imported file
    /// carries its own duration, which was simply being dropped.
    private var confirmedDuration: TimeInterval? {
        switch mode {
        case .speak:
            if case .recordedAudio(let recording) = speakVM.speechSource { return recording.duration }
            return nil
        case .attachFile:
            if case .importedMedia(let media) = attachVM.speechSource { return media.duration }
            return nil
        case .write:
            return nil
        }
    }

    static let untitledTitle = "Untitled Script"

    /// Restores a title carried back from a later step, so returning after a failure does
    /// not cost the user the name they typed.
    ///
    /// `makeDraft` substitutes `untitledTitle` when the field was blank, so that exact value
    /// means "never named" rather than "named Untitled Script". Writing it back verbatim
    /// would put words in the field the user did not type — and, worse, turn a placeholder
    /// into real content they would then have to delete.
    func restoreTitle(from draftTitle: String) {
        title = draftTitle == Self.untitledTitle ? "" : draftTitle
    }

    /// `true` when the currently active mode has enough content to proceed.
    public var hasValidContent: Bool {
        hasContent(in: mode)
    }

    /// Whether the given mode currently holds content a user could lose by confirming.
    private func hasContent(in mode: InputMode) -> Bool {
        switch mode {
        case .speak: speakVM.canProceed
        case .write: writeVM.hasContent
        case .attachFile: attachVM.hasImportedFile
        }
    }

    /// Modes other than the active one that still hold content confirming would discard.
    ///
    /// Confirming commits to a single mode — `discardUnconfirmedModes()` drops the other
    /// two, and a Speak take is a real audio file on disk that v1 offers no way to recover.
    /// When any inactive mode holds real content the confirm flow warns first, so a
    /// recording or a typed draft is never silently thrown away. Returned in
    /// `InputMode.allCases` order so the warning message reads consistently.
    public var unconfirmedModesWithContent: [InputMode] {
        InputMode.allCases.filter { $0 != mode && hasContent(in: $0) }
    }

    /// Sentence for the confirm dialog naming the modes that won't be processed.
    ///
    /// Empty when the active mode is the only one holding content; the confirm flow reads
    /// `unconfirmedModesWithContent` to decide whether to show the dialog at all, so this is
    /// only ever displayed when at least one mode is named.
    public var discardWarningMessage: String {
        let names = unconfirmedModesWithContent.map(\.title)
        guard !names.isEmpty else { return "" }
        let list = ListFormatter.localizedString(byJoining: names)
        return "Only your \(mode.title) input will be processed. "
            + "Your \(list) input will be ignored and won't be saved."
    }

    private let generateTranscript: GenerateTranscriptUseCase

    /// - Parameter initialText: text to open in Write mode, used when analysis rejected a
    ///   transcript and handed it back to be edited. Opening in Write mode rather than the
    ///   default Speak mode is the point: the user already has the words, and what they
    ///   need now is to change them, not to record again.
    public init(
        purpose: SpeechPurpose,
        fileImporter: any FileImporting,
        audioCapturer: any AudioCapturing,
        microphonePermissions: any MicrophonePermissionProviding,
        generateTranscript: GenerateTranscriptUseCase,
        initialText: String? = nil
    ) {
        self.purpose = purpose
        self.generateTranscript = generateTranscript
        self.speakVM = SpeakModeViewModel(capturer: audioCapturer, permissions: microphonePermissions)
        self.writeVM = WriteModeViewModel()
        self.attachVM = AttachFileModeViewModel(fileImporter: fileImporter)

        if let initialText, !initialText.isEmpty {
            writeVM.content = initialText
            mode = .write
        }
    }

    /// Abandons any in-flight work and releases the resources behind it.
    ///
    /// Must be called when leaving the screen without confirming: a Speak session that is
    /// merely dropped keeps the audio engine running and the audio session active — the
    /// microphone stays live behind a screen the user has already left.
    public func discard() {
        speakVM.cancel()
        attachVM.cancel()
        dismissLoading()
    }

    /// Finalizes the active mode and moves to the transcription step.
    ///
    /// Does nothing when the active mode has no content — the confirm button is disabled
    /// in that case, but Speak mode can still finish empty.
    public func proceed() async {
        guard let source = await prepareToProceed() else { return }
        loadingVM = LoadingRouteViewModel(source: source, generateTranscript: generateTranscript)
    }

    /// Leaves the transcription step, cancelling any in-flight work.
    public func dismissLoading() {
        loadingVM?.cancel()
        loadingVM = nil
    }

    /// Finalizes the active mode and returns its content as a domain `SpeechSource` —
    /// the single contract the next step consumes, regardless of which mode produced it
    /// (ARCHITECTURE.md §3.2.1).
    ///
    /// Speak mode has real work to do here (ending the session, flushing the transcript),
    /// which is why this is async and why callers must not read `speechSource` instead.
    ///
    /// Confirming does **not** discard anything. Transcription can still fail, and the user
    /// returns here with every mode exactly as they left it — see `discardUnconfirmedModes()`
    /// for where the commitment actually happens.
    public func prepareToProceed() async -> SpeechSource? {
        switch mode {
        case .speak:
            // Ends the capture session and flushes the file. The resulting `.finished`
            // state keeps the take on screen, so returning here after a failure shows the
            // recording rather than an empty recorder.
            _ = await speakVM.finish()
            return speakVM.speechSource
        case .write:
            return writeVM.speechSource
        case .attachFile:
            return attachVM.speechSource
        }
    }

    /// Releases the two modes the user did not confirm.
    ///
    /// Called at the point of no return — when analysis takes over — rather than when the
    /// user confirms. Confirming looks like commitment but isn't: transcription can fail,
    /// and the user comes straight back to this screen expecting their work intact, in
    /// whichever mode they were in. Discarding at confirm time would delete a recording
    /// they are about to be handed back.
    ///
    /// This matters most for Speak, where `cancel()` discards a real audio file on disk;
    /// leaving it would leak storage the user has no way to reclaim, since v1 ships no
    /// deletion UI. Attach File needs no file cleanup — import is bookmark-based and never
    /// copies into the sandbox — so cancelling it only drops the reference.
    func discardUnconfirmedModes() {
        if mode != .speak { speakVM.cancel() }
        if mode != .attachFile { attachVM.cancel() }
        if mode != .write { writeVM.content = "" }
    }
}
