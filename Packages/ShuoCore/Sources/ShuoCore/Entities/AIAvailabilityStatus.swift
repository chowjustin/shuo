//
//  AIAvailabilityStatus.swift
//  ShuoCore
//

// Whether the on-device model can run right now, stated without reference to
// FoundationModels. Mirrors `SystemLanguageModel.Availability` so the presentation layer
// can react without importing the framework.

import Foundation

/// Whether on-device generation is currently possible.
///
/// Only two of the unavailable cases are recoverable at runtime, and the UI treats them
/// very differently — one is a wait, the other is an instruction — which is why this is an
/// enum rather than a bool (CLAUDE.md §8).
public enum AIAvailabilityStatus: Sendable, Equatable {
    case available
    /// The hardware cannot run Apple Intelligence at all. v1 requires eligible hardware,
    /// so this is a hard block enforced at onboarding rather than something the analysis
    /// flow degrades around — there is no no-AI mode (CLAUDE.md §11).
    case deviceNotEligible
    /// Eligible hardware with Apple Intelligence switched off. Actionable: send the user
    /// to Settings.
    case appleIntelligenceNotEnabled
    /// Assets are still downloading or warming up. Transient — show the loading state and
    /// retry rather than reporting a failure.
    case modelNotReady

    /// True only when generation can be attempted.
    public var isAvailable: Bool {
        self == .available
    }

    /// True when waiting and retrying is the right response, as opposed to telling the
    /// user to do something.
    public var isTransient: Bool {
        self == .modelNotReady
    }
}
