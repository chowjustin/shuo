//
//  TranscriptionInput.swift
//  ShuoCore
//

import Foundation

/// The two kinds of on-disk media that can be transcribed after the fact.
///
/// Narrower than `SpeechSource` on purpose: `.typedText` needs no transcription at all,
/// so admitting it here would force every conformer to handle a case that can never
/// legitimately reach it. `GenerateTranscriptUseCase` owns that filtering.
///
/// The two cases stay distinct because their file access differs — an `ImportedMedia`
/// lives outside the sandbox and must be reached through `resolveURL()`, while an
/// `AudioRecording` is a file the app wrote itself and can be opened directly.
public enum TranscriptionInput: Sendable, Equatable {
    /// A file the user attached. Access requires resolving its security-scoped bookmark.
    case importedMedia(ImportedMedia)
    /// A recording the app captured. Already inside the sandbox.
    case recordedAudio(AudioRecording)
}
