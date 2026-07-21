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
    /// The recording or file runs shorter than `MediaLimits.minDurationSeconds`. Raised
    /// before transcription rather than after: a sub-3s take cannot hold a speech worth
    /// structuring, so transcribing it only to report `noSpeechDetected` spends a round
    /// trip and blames the user for a fault that was predictable from the duration alone.
    case mediaTooShort
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
    /// The transcript is not a usable speech script — too short, silent, unintelligible,
    /// or simply not a speech (a wrong file, a shopping list). Carries the reason so the
    /// UI can show actionable copy rather than a generic failure. Raised by
    /// `ClassifyTranscriptUseCase`, from either the zero-cost precheck or the model's own
    /// usability verdict.
    case transcriptNotUsable(TranscriptRejectionReason)
    /// Generation ran but produced nothing usable — the model returned no valid pattern
    /// ids, or refinement came back empty. Distinct from `aiUnavailable` (the model can't
    /// run at all) because this one is worth retrying.
    case aiGenerationFailed

    // MARK: - Persistence

    case persistenceFailed

    // MARK: - Recording

    /// The user declined microphone access, or it is restricted. Only Settings can
    /// change this — re-requesting will not prompt again.
    case microphonePermissionDenied
    /// Audio capture could not start, or produced nothing usable.
    case recordingFailed
}
