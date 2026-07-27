//
//  TranscriptAnalysisViewState.swift
//  FeatureTranscriptAnalysis
//

// The analysis screen's top-level state, as an enum so illegal combinations are
// unrepresentable (CLAUDE.md §5).

import Foundation
import ShuoCore

/// What the analysis screen is showing.
///
/// An enum rather than a set of booleans specifically because `isLoading && rejectionReason
/// != nil && keyPoints.isEmpty` is the kind of contradictory state that scattered flags
/// make possible and enums make impossible (CLAUDE.md §5).
///
/// This covers the *initial* load only. Once `.loaded`, per-pattern regeneration and
/// refinement report through separate in-place flags — switching a pattern is an inline
/// update, not a return to a full-screen loading state, and modelling it as one would make
/// the screen flash back to a spinner on every tap.
public enum TranscriptAnalysisViewState: Equatable, Sendable {
    /// Classifying the transcript and generating key points for the top pattern.
    case analyzing
    /// The on-device model exists but isn't ready yet — assets still downloading or warming
    /// up. Transient, and resolved by waiting rather than by the user doing anything, so it
    /// is a loading state and not a failure (ARCHITECTURE.md §3.2.4).
    case waitingForModel
    /// Generation cannot run and waiting will not change that. Carries the status because
    /// `ShuoError.aiUnavailable` has no payload and the two reachable causes need different
    /// copy: one is a Settings toggle, the other is the hardware.
    case unavailable(AIAvailabilityStatus)
    /// The transcript is not a usable speech script. Terminal — the user's recourse is to
    /// go back and provide different input.
    case rejected(TranscriptRejectionReason)
    /// Patterns and key points are on screen.
    case loaded
    /// Analysis failed for a reason that is not the user's content. Retryable.
    case failed(ShuoError)
}

// Which toolbar controls each state offers lives in `AnalysisToolbarControls`, since it
// depends on more than this enum — a script reopened from the library has no step to go
// back to.
