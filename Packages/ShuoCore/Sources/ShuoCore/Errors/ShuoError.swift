//
//  ShuoError.swift
//  ShuoCore
//

import Foundation

public enum ShuoError: Error, Sendable, Equatable {
    // MARK: - Import

    /// The chosen file exceeds `MediaLimits.maxFileSizeBytes`.
    case fileTooLarge
    /// The chosen file runs longer than `MediaLimits.maxDurationSeconds`. Deliberately
    /// distinct from `fileTooLarge`: a short 4K video can be huge and a long podcast can
    /// be tiny, so duration — not bytes — is what actually bounds transcription time and
    /// the model's context window.
    case mediaTooLong
    /// The file is neither audio nor video. The picker filters these out, but a file can
    /// still arrive with a misleading extension or an unreadable type.
    case unsupportedMediaType
    /// The file could not be bookmarked, or security-scoped access was refused.
    case importFailed

    // MARK: - Audio extraction

    /// A video attachment carried no audio track, or the export failed.
    case audioExtractionFailed

    // MARK: - Transcription

    /// The user declined speech recognition, or it is restricted. Only Settings can
    /// change this — re-requesting will not prompt again.
    case speechPermissionDenied
    /// On-device speech assets for the app's locale are missing or still downloading.
    case speechModelUnavailable
    /// Transcription completed but produced no words — a silent or music-only file.
    case noSpeechDetected
    /// Transcription failed for any other reason.
    case transcriptionFailed

    // MARK: - AI

    case aiUnavailable
    case contextWindowExceeded

    // MARK: - Persistence

    case persistenceFailed

    // MARK: - Recording

    /// The user declined microphone access, or it is restricted. Only Settings can
    /// change this — re-requesting will not prompt again.
    case microphonePermissionDenied
    /// Audio capture could not start, or produced nothing usable.
    case recordingFailed
}
