//
//  SpeakModeViewState.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 17/07/26.
//

import Foundation
import ShuoCore

/// The Speak screen's state, as an enum so combinations like "recording but permission
/// denied" cannot be represented (CLAUDE.md §5).
public enum SpeakModeViewState: Equatable {
    /// Nothing captured yet. Shows the prompt and the microphone button.
    case idle
    /// Waiting on the system permission prompt.
    case requestingPermission
    /// Microphone access refused. Only Settings can undo this, so the UI offers a link
    /// there rather than a retry.
    case permissionDenied
    case recording
    /// Suspended, by the user or by an interruption. Audio so far is retained, and this
    /// is the state from which the user can proceed.
    case paused
    case finished(AudioRecording)
    case failed(String)
}
