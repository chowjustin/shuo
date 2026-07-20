//
//  TranscriptionErrorCopy.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 20/07/26.
//

import Foundation
import ShuoCore

/// User-facing wording for every failure the attach-file flow can hit.
///
/// The mapping lives in the feature package rather than in `ShuoError` itself: the domain
/// says *what* went wrong, the presentation layer decides how to say it. It is also why
/// `ShuoDesignSystem.ErrorSheet` takes plain strings — it never sees a domain type
/// (CLAUDE.md §4).
struct TranscriptionErrorCopy: Equatable {
    /// What the primary button actually does. Modelled explicitly rather than inferred
    /// from the button's title, so changing copy can never change behaviour.
    enum Action: Equatable {
        /// Reopen the file picker — a different file is the real fix.
        case pickAnotherFile
        /// Retry the same source; the failure was transient.
        case retry
        /// Nothing in-app will help (a permission only Settings can grant). Leave.
        case close
    }

    let systemImage: String
    let title: String
    let message: String
    let primaryActionTitle: String
    let primaryAction: Action

    // Every case is spelled out rather than defaulted, so adding a `ShuoError` case
    // fails the build here instead of silently shipping generic copy.
    init(error: ShuoError) {
        switch error {
        case .fileTooLarge:
            self.init(
                systemImage: "doc.badge.exclamationmark",
                title: "File too large.",
                message: "Maximum file size: \(MediaLimits.formattedMaxFileSize)",
                primaryActionTitle: "Choose another file",
                primaryAction: .pickAnotherFile
            )

        case .mediaTooLong:
            self.init(
                systemImage: "clock.badge.exclamationmark",
                title: "Recording too long.",
                message: "Shuo can work with speeches up to \(MediaLimits.formattedMaxDuration). Try a shorter clip.",
                primaryActionTitle: "Choose another file",
                primaryAction: .pickAnotherFile
            )

        case .unsupportedMediaType:
            self.init(
                systemImage: "doc.questionmark",
                title: "That file isn't audio or video.",
                message: "Attach an audio recording or a video, and Shuo will transcribe the speech in it.",
                primaryActionTitle: "Choose another file",
                primaryAction: .pickAnotherFile
            )

        case .importFailed:
            self.init(
                systemImage: "folder.badge.questionmark",
                title: "We couldn't open that file.",
                message: "It may have been moved, renamed, or deleted since you picked it.",
                primaryActionTitle: "Choose another file",
                primaryAction: .pickAnotherFile
            )

        case .audioExtractionFailed:
            self.init(
                systemImage: "video.slash",
                title: "No audio in that video.",
                message: "This video has no sound track, so there's nothing to transcribe.",
                primaryActionTitle: "Choose another file",
                primaryAction: .pickAnotherFile
            )

        case .noSpeechDetected:
            self.init(
                systemImage: "waveform.slash",
                title: "We couldn't hear any speech.",
                message: "This file seems to be silent, or contains only music or background noise.",
                primaryActionTitle: "Choose another file",
                primaryAction: .pickAnotherFile
            )

        case .speechPermissionDenied:
            // Re-requesting will not prompt again — only Settings can change this, so the
            // action must not pretend a retry will help.
            self.init(
                systemImage: "mic.slash",
                title: "Speech recognition is turned off.",
                message: "Shuo needs speech recognition to turn your audio into text. You can turn it back on in Settings › Shuo.",
                primaryActionTitle: "Close",
                primaryAction: .close
            )

        case .speechModelUnavailable:
            self.init(
                systemImage: "arrow.down.circle.dotted",
                title: "Speech model not ready.",
                message: "The on-device speech model is still downloading. Connect to Wi-Fi and try again in a few minutes.",
                primaryActionTitle: "Try again",
                primaryAction: .retry
            )

        case .transcriptionFailed:
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                title: "Transcription failed.",
                message: "Something went wrong while reading this file. Please try again.",
                primaryActionTitle: "Try again",
                primaryAction: .retry
            )

        case .microphonePermissionDenied:
            self.init(
                systemImage: "mic.slash",
                title: "Microphone access is off.",
                message: "Shuo needs your microphone to record. You can turn it back on in Settings › Shuo.",
                primaryActionTitle: "Close",
                primaryAction: .close
            )

        case .recordingFailed:
            self.init(
                systemImage: "waveform.badge.exclamationmark",
                title: "Recording failed.",
                message: "We couldn't capture that recording. Please try again.",
                primaryActionTitle: "Try again",
                primaryAction: .retry
            )

        case .aiUnavailable, .contextWindowExceeded, .persistenceFailed:
            // Not reachable from the attach-file flow yet; these belong to the analysis
            // and saving steps, which are not built. Deliberately generic until they are.
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                title: "Something went wrong.",
                message: "Please try again.",
                primaryActionTitle: "Try again",
                primaryAction: .retry
            )
        }
    }

    private init(
        systemImage: String,
        title: String,
        message: String,
        primaryActionTitle: String,
        primaryAction: Action
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
    }
}
