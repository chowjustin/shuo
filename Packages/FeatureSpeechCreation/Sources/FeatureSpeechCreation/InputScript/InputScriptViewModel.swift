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

    /// `true` when the currently active mode has enough content to proceed.
    public var hasValidContent: Bool {
        switch mode {
        case .speak: speakVM.canProceed
        case .write: writeVM.hasContent
        case .attachFile: attachVM.hasImportedFile
        }
    }

    public init(
        purpose: SpeechPurpose,
        fileImporter: any FileImporting,
        audioCapturer: any AudioCapturing,
        microphonePermissions: any MicrophonePermissionProviding
    ) {
        self.purpose = purpose
        self.speakVM = SpeakModeViewModel(capturer: audioCapturer, permissions: microphonePermissions)
        self.writeVM = WriteModeViewModel()
        self.attachVM = AttachFileModeViewModel(fileImporter: fileImporter)
    }

    /// Abandons any in-flight work and releases the resources behind it.
    ///
    /// Must be called when leaving the screen without confirming: a Speak session that is
    /// merely dropped keeps the audio engine running and the audio session active — the
    /// microphone stays live behind a screen the user has already left.
    public func discard() {
        speakVM.cancel()
        attachVM.cancel()
    }

    /// Finalizes the active mode and returns its content as a domain `SpeechSource` —
    /// the single contract the next step consumes, regardless of which mode produced it
    /// (ARCHITECTURE.md §3.2.1).
    ///
    /// Speak mode has real work to do here (ending the session, flushing the transcript),
    /// which is why this is async and why callers must not read `speechSource` instead.
    public func prepareToProceed() async -> SpeechSource? {
        switch mode {
        case .speak:
            _ = await speakVM.finish()
            return speakVM.speechSource
        case .write:
            return writeVM.speechSource
        case .attachFile:
            return attachVM.speechSource
        }
    }
}
