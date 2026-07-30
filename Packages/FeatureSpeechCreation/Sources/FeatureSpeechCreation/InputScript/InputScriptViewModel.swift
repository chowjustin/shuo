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
        ScriptDraft(
            title: resolvedTitle,
            purpose: purpose,
            transcript: transcript,
            recordingDuration: confirmedDuration
        )
    }

    /// The title as it would be saved: what the user typed, or the numbered fallback if they
    /// typed nothing. Read by the coordinator when it carries a rename forward into an
    /// analysis the user is returning to rather than starting over.
    public var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledPlaceholder : trimmed
    }

    /// The name a blank title falls back to — `Untitled Script 1`, `Untitled Script 2`, …
    ///
    /// Held as state rather than computed because numbering requires reading what is
    /// already stored, which is async, while `resolvedTitle` is read synchronously by
    /// `makeDraft` and by the coordinator on the way forward. `prepareUntitledPlaceholder()`
    /// settles it while the user is still recording or typing, so neither of those has to
    /// become async and neither can block on I/O at the moment the user taps ✓.
    public private(set) var untitledPlaceholder: String = UntitledScriptTitle.first

    /// True once `untitledPlaceholder` is settled — resolved from the store, or adopted from
    /// a draft coming back from analysis.
    ///
    /// Adoption has to win over resolution. By the time the user steps back, analysis has
    /// already saved this script under its generated name (`ARCHITECTURE.md` §16), so
    /// re-resolving would find that record and number *past* it — silently renaming the
    /// user's script from `Untitled Script 1` to `Untitled Script 2` for the crime of
    /// stepping back and confirming again.
    private var isPlaceholderSettled = false

    /// Internal rather than private so tests can await the resolve, matching
    /// `SpeakModeViewModel.transitionTask` and `AttachFileModeViewModel.importTask`.
    var placeholderTask: Task<Void, Never>?

    /// Resolves the fallback name, before the user can reach the step that saves it.
    ///
    /// Idempotent, because the input step is re-entered rather than rebuilt and its `.task`
    /// runs again each time. A failed read deliberately leaves this unsettled so a later
    /// attempt can retry: `UntitledScriptTitle.first` stands in meanwhile, since a store
    /// that cannot be read is about to fail at save time with a real error, and blocking the
    /// whole input step over the *name* of an untitled script would be a poor trade.
    public func prepareUntitledPlaceholder() {
        guard !isPlaceholderSettled else { return }
        placeholderTask?.cancel()
        placeholderTask = Task { [weak self] in
            guard let self else { return }
            guard let next = try? await nextUntitledTitle() else { return }
            guard !Task.isCancelled, !isPlaceholderSettled else { return }
            untitledPlaceholder = next
            isPlaceholderSettled = true
        }
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
            if case let .recordedAudio(recording) = speakVM.speechSource {
                return recording.duration
            }
            return nil
        case .attachFile:
            if case let .importedMedia(media) = attachVM.speechSource {
                return media.duration
            }
            return nil
        case .write:
            return nil
        }
    }

    /// Restores a title carried back from a later step, so returning after a failure does
    /// not cost the user the name they typed.
    ///
    /// `makeDraft` substitutes a generated `Untitled Script N` when the field was blank, so
    /// any generated name means "never named" rather than "named that". Writing it back
    /// verbatim would put words in the field the user did not type — and, worse, turn a
    /// placeholder into real content they would then have to delete. Recognised by pattern
    /// rather than by equality now that the name carries a number.
    func restoreTitle(from draftTitle: String) {
        guard UntitledScriptTitle.isGenerated(draftTitle) else {
            title = draftTitle
            return
        }
        // Adopt the number this script already has instead of leaving the field to be
        // renumbered — see `isPlaceholderSettled`.
        untitledPlaceholder = draftTitle
        isPlaceholderSettled = true
        title = ""
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
    /// Confirming sends exactly one mode forward, and only that one becomes a speech.
    /// Nothing is deleted at that point — the user can step back and the other modes are
    /// still here — but a user who recorded a take *and* typed a draft would otherwise
    /// watch one of them silently not happen. Returned in `InputMode.allCases` order so
    /// the warning message reads consistently.
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
    private let nextUntitledTitle: NextUntitledScriptTitleUseCase

    /// - Parameters:
    ///   - makeAudioCapturer: builds a capture session. A factory rather than an instance
    ///     because `AudioCapturing` is single-use — see `SpeakModeViewModel`.
    ///   - nextUntitledTitle: names a script the user never titled. Needed here rather than
    ///     only at save time because the number has to be settled before `makeDraft` mints
    ///     the draft, so the name the analysis screen shows is the name that gets saved.
    ///   - initialText: text to open in Write mode, used when this step is rebuilt rather
    ///     than resumed. Opening in Write mode rather than the default Speak mode is the
    ///     point: the user already has the words, and what they need now is to change
    ///     them, not to record again.
    public init(
        purpose: SpeechPurpose,
        fileImporter: any FileImporting,
        makeAudioCapturer: @escaping @Sendable () -> any AudioCapturing,
        microphonePermissions: any MicrophonePermissionProviding,
        audioPlayer: any AudioPlaying,
        recordingDeleter: any AudioRecordingDeleting,
        generateTranscript: GenerateTranscriptUseCase,
        nextUntitledTitle: NextUntitledScriptTitleUseCase,
        initialText: String? = nil
    ) {
        self.purpose = purpose
        self.generateTranscript = generateTranscript
        self.nextUntitledTitle = nextUntitledTitle
        speakVM = SpeakModeViewModel(
            makeCapturer: makeAudioCapturer,
            permissions: microphonePermissions,
            player: audioPlayer,
            recordingDeleter: recordingDeleter
        )
        writeVM = WriteModeViewModel()
        attachVM = AttachFileModeViewModel(fileImporter: fileImporter)

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
        placeholderTask?.cancel()
        placeholderTask = nil
        dismissLoading()
    }

    /// Opens the transcription step on an already-confirmed source.
    ///
    /// Separate from `prepareToProceed()` because the coordinator decides between the two
    /// things that can follow a ✓ — transcribing afresh, or returning to an analysis the
    /// user already has for this exact source — and only one of them involves this screen.
    public func beginTranscription(of source: SpeechSource) {
        loadingVM?.cancel()
        loadingVM = LoadingRouteViewModel(
            source: source,
            purpose: purpose,
            generateTranscript: generateTranscript
        )
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
    /// Confirming does **not** discard anything. Transcription can fail, and analysis can
    /// be stepped back out of, and in both cases the user returns here with every mode
    /// exactly as they left it — including a recording they can still play back. The
    /// modes are released only when the flow itself ends, in `discard()`.
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

    /// Parks a transcript the analysis step handed back, so the words are within reach
    /// without taking over the screen.
    ///
    /// Stepping back from analysis returns the user to the mode they left — a recording
    /// they can still play, not a wall of transcribed text (`ARCHITECTURE.md` §6). But
    /// when analysis rejected the transcript, changing the wording *is* the fix, so the
    /// text is left waiting in Write mode for a user who switches tabs to look for it.
    ///
    /// Never overwrites: anything already typed there is the user's, and worth more than
    /// a transcript they can regenerate.
    func stashTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, mode != .write, !writeVM.hasContent else { return }
        writeVM.content = trimmed
    }
}
