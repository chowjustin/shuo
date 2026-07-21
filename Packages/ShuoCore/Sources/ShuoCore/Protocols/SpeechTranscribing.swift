//
//  SpeechTranscribing.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// Turns a media file into text.
///
/// Conformers own everything the domain must not know about: resolving security-scoped
/// bookmarks, extracting the audio track from a video, requesting speech authorization,
/// and translating framework failures into `ShuoError` at the package boundary.
public protocol SpeechTranscribing: Sendable {
    /// Transcribes `input` and returns its text.
    ///
    /// - Returns: the transcript, always non-empty and trimmed.
    /// - Throws: `ShuoError.noSpeechDetected` when the media contains no recognizable
    ///   speech, `.speechPermissionDenied` when authorization was refused,
    ///   `.speechModelUnavailable` when on-device assets are missing,
    ///   `.audioExtractionFailed` when a video's audio track could not be read, or
    ///   `.transcriptionFailed` for anything else.
    func transcribe(_ input: TranscriptionInput) async throws -> String
}
