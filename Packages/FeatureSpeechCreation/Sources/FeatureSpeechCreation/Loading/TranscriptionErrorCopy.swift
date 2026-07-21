//
//  TranscriptionErrorCopy.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 20/07/26.
//

import Foundation
import ShuoCore

/// User-facing wording for every failure the transcription step can hit.
///
/// The mapping lives in the feature package rather than in `ShuoError` itself: the domain
/// says *what* went wrong, the presentation layer decides how to say it. It is also why
/// `ShuoDesignSystem.ErrorSheet` takes plain strings — it never sees a domain type
/// (CLAUDE.md §4).
///
/// **Copy only — no action.** This deliberately carries no "primary action", because it
/// cannot know what produced the error: `noSpeechDetected` arrives from a recording just as
/// readily as from a file, and the version of this type that tried to choose offered
/// "choose another file" to users who had recorded. Every failure here resolves on the
/// input screen, which is one ‹ away, so the wording tells the user what went wrong and
/// lets that one button do the rest.
struct TranscriptionErrorCopy: Equatable {
    let systemImage: String
    let title: String
    let message: String

    // Every case is spelled out rather than defaulted, so adding a `ShuoError` case
    // fails the build here instead of silently shipping generic copy.
    init(error: ShuoError) {
        switch error {
        case .fileTooLarge:
            self.init(
                systemImage: "doc.badge.exclamationmark",
                title: "File too large.",
                message: "Maximum file size: \(MediaLimits.formattedMaxFileSize)"
            )

        case .mediaTooLong:
            self.init(
                systemImage: "clock.badge.exclamationmark",
                title: "Recording too long.",
                message: "Shuo can work with speeches up to \(MediaLimits.formattedMaxDuration). Try a shorter clip."
            )

        // Phrased for both sources, because it reaches here from a brief recording as
        // readily as from a short file — the wording that named one of them was the bug
        // this type's action mapping used to have.
        case .mediaTooShort:
            self.init(
                systemImage: "clock.badge.exclamationmark",
                title: "That's too short to work with.",
                message: "Shuo needs at least \(MediaLimits.formattedMinDuration) of speech to suggest a structure. Go back and add a little more."
            )

        case .unsupportedMediaType:
            self.init(
                systemImage: "doc.questionmark",
                title: "That file isn't audio or video.",
                message: "Attach an audio recording or a video, and Shuo will transcribe the speech in it."
            )

        case .importFailed:
            self.init(
                systemImage: "folder.badge.questionmark",
                title: "We couldn't open that file.",
                message: "It may have been moved, renamed, or deleted since you picked it."
            )

        case .audioExtractionFailed:
            self.init(
                systemImage: "video.slash",
                title: "No audio in that video.",
                message: "This video has no sound track, so there's nothing to transcribe."
            )

        case .noSpeechDetected:
            self.init(
                systemImage: "waveform.slash",
                title: "We couldn't hear any speech.",
                message: "This file seems to be silent, or contains only music or background noise."
            )

        case .speechPermissionDenied:
            // Re-requesting will not prompt again — only Settings can change this, so the
            // action must not pretend a retry will help.
            self.init(
                systemImage: "mic.slash",
                title: "Speech recognition is turned off.",
                message: "Shuo needs speech recognition to turn your audio into text. You can turn it back on in Settings › Shuo."
            )

        case .speechModelUnavailable:
            self.init(
                systemImage: "arrow.down.circle.dotted",
                title: "Speech model not ready.",
                message: "The on-device speech model is still downloading. Connect to Wi-Fi and try again in a few minutes."
            )

        case .transcriptionFailed:
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                title: "Transcription failed.",
                message: "Something went wrong while reading this file. Please try again."
            )

        case .microphonePermissionDenied:
            self.init(
                systemImage: "mic.slash",
                title: "Microphone access is off.",
                message: "Shuo needs your microphone to record. You can turn it back on in Settings › Shuo."
            )

        case .recordingFailed:
            self.init(
                systemImage: "waveform.badge.exclamationmark",
                title: "Recording failed.",
                message: "We couldn't capture that recording. Please try again."
            )

        case .aiUnavailable, .contextWindowExceeded, .persistenceFailed,
             .transcriptNotUsable, .aiGenerationFailed:
            // Not reachable from this flow: these belong to the analysis and saving steps,
            // which own their own copy — `TranscriptAnalysisView` maps every
            // `TranscriptRejectionReason` to its own actionable wording. Kept generic here
            // rather than duplicated, since the attach-file sheet never shows them.
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                title: "Something went wrong.",
                message: "Please try again."
            )
        }
    }

    private init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }
}
