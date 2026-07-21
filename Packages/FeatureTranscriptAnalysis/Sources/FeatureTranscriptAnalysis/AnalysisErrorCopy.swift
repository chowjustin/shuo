//
//  AnalysisErrorCopy.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 21/07/26.
//

import Foundation
import ShuoCore

/// User-facing wording for every failure the analysis step can hit.
///
/// The same split as `FeatureSpeechCreation.TranscriptionErrorCopy`: the domain says *what*
/// went wrong, the presentation layer decides how to say it, and `ShuoDesignSystem.ErrorSheet`
/// takes plain strings so it never sees a domain type (CLAUDE.md §4). Duplicated rather than
/// shared because the two features must not depend on each other, and because the same error
/// warrants different advice here — this screen has no file picker to send the user back to.
struct AnalysisErrorCopy: Equatable {
    let systemImage: String
    let title: String
    let message: String

    /// Copy for a transcript the analysis judged unusable.
    ///
    /// None of these offer a retry: the verdict is about the user's content, so running the
    /// same transcript through the same model would reach the same conclusion. The recourse
    /// is different input, which means leaving this screen.
    init(reason: TranscriptRejectionReason) {
        switch reason {
        case .tooShort:
            self.init(
                systemImage: "text.badge.xmark",
                title: "There isn't enough here yet.",
                message: "We need a bit more of your speech before we can suggest a structure. Try again with a longer draft."
            )

        case .mostlySilence:
            self.init(
                systemImage: "waveform.slash",
                title: "We couldn't hear any speech.",
                message: "This recording seems to be silent, or contains only background noise. Try recording again somewhere quieter."
            )

        case .unintelligible:
            self.init(
                systemImage: "questionmark.bubble",
                title: "We couldn't make out any words.",
                message: "Check this is the file you meant to use, and that it's a recording of someone speaking."
            )

        case .notASpeech:
            self.init(
                systemImage: "doc.questionmark",
                title: "This doesn't look like a speech.",
                message: "Shuo works with talks and speeches. Check you picked the right file, or try writing your ideas instead."
            )
        }
    }

    /// Copy for on-device generation being unavailable.
    ///
    /// Separate from `init(error:)` because `ShuoError.aiUnavailable` carries no payload,
    /// and the two reachable causes are not the same message: one is a switch the user can
    /// flip, the other is the device they own. Flattening both into one wording would either
    /// send an ineligible user hunting through Settings for a toggle that will not help, or
    /// tell a user with the toggle off that their phone is unsupported.
    init(availability: AIAvailabilityStatus) {
        switch availability {
        case .appleIntelligenceNotEnabled:
            // No retry: nothing in this app can turn Apple Intelligence on, so a confirm
            // button here would fail every time it was pressed. ✕ is the honest exit, the
            // same reasoning as `init(reason:)`.
            self.init(
                systemImage: "sparkles.slash",
                title: "Apple Intelligence is turned off.",
                message: "Shuo analyzes your speech on this device using Apple Intelligence. Turn it on in Settings › Apple Intelligence & Siri, then come back."
            )

        case .deviceNotEligible:
            // A hard block, stated plainly. v1 requires eligible hardware and has no
            // degraded mode (ARCHITECTURE.md §2.1), so implying a fix would be a lie.
            self.init(
                systemImage: "iphone.slash",
                title: "This device can't run Shuo's analysis.",
                message: "Shuo works out your speech's structure on-device, which needs a device that supports Apple Intelligence. There's no setting that changes this."
            )

        case .modelNotReady:
            // Rendered as `LoadingView`, not as an error sheet — waiting is the response,
            // and calling it a failure would tell the user to act on something that is
            // already resolving itself. Kept here only so the switch stays exhaustive and
            // no status can reach a blank sheet.
            self.init(
                systemImage: "arrow.down.circle",
                title: "Apple Intelligence is still getting ready.",
                message: "The on-device model is finishing its setup. This will continue on its own once it's done."
            )

        case .available:
            // Unreachable: nothing asks for error copy while generation is possible.
            self.init(
                systemImage: "exclamationmark.triangle.fill",
                title: "The analysis didn't start.",
                message: "Something went wrong before we could look at your speech. Trying again usually fixes it."
            )
        }
    }

    // Every case is spelled out rather than defaulted, so adding a `ShuoError` case fails
    // the build here instead of silently shipping generic copy.
    init(error: ShuoError) {
        switch error {
        case .transcriptNotUsable(let reason):
            // Reachable if a rejection escapes as a plain failure rather than through
            // `.rejected`. Deferring keeps one wording per reason either way.
            self.init(reason: reason)

        case .aiUnavailable:
            self.init(
                systemImage: "sparkles.slash",
                title: "Apple Intelligence isn't available.",
                message: "Shuo needs Apple Intelligence to analyze your speech. You can turn it on in Settings › Apple Intelligence & Siri."
            )

        case .contextWindowExceeded:
            self.init(
                systemImage: "text.append",
                title: "That speech is a bit too long.",
                message: "There's more here than we can analyze in one pass. Try again with a shorter section."
            )

        case .aiGenerationFailed:
            self.init(
                systemImage: "sparkles",
                title: "Analysis didn't finish.",
                message: "Something went wrong while working through your speech. Trying again usually fixes it."
            )

        case .persistenceFailed:
            self.init(
                systemImage: "externaldrive.badge.exclamationmark",
                title: "We couldn't save this script.",
                message: "Your work is still on screen. Try saving again."
            )

        case .fileTooLarge, .mediaTooLong, .mediaTooShort, .unsupportedMediaType,
             .importFailed, .audioExtractionFailed, .speechPermissionDenied,
             .speechModelUnavailable, .noSpeechDetected, .transcriptionFailed,
             .microphonePermissionDenied, .recordingFailed:
            // Not reachable from this screen: these belong to import, recording, and
            // transcription, which finish before analysis begins and own their own copy in
            // `TranscriptionErrorCopy`. Kept generic rather than duplicated.
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
