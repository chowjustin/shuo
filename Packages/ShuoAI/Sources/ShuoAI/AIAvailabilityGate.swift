//
//  AIAvailabilityGate.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Conforms to `AIAvailabilityChecking` (ShuoCore); wraps
// `SystemLanguageModel.default.availability`. For v1, only needs to handle
// `.modelNotReady` (poll/retry with the Loading UI) and `.appleIntelligenceNotEnabled`
// (actionable Settings prompt) gracefully — `.deviceNotEligible` is a hard block
// enforced earlier, at onboarding. See ARCHITECTURE.md §3.2.4, CLAUDE.md §8.

import Foundation
import FoundationModels
import ShuoCore

/// Reports on-device model availability, translated into domain terms.
///
/// Reads `SystemLanguageModel.default.availability` on every call rather than caching it:
/// assets can finish downloading, and Apple Intelligence can be switched on in Settings,
/// while the app is running. A cached "unavailable" would strand the user on an error
/// screen after they had already fixed the problem.
public struct AIAvailabilityGate: AIAvailabilityChecking {

    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public func availability() async -> AIAvailabilityStatus {
        Self.status(for: model.availability)
    }

    /// Translates the framework's availability into the domain enum.
    ///
    /// Split out as a pure static function so it can be tested without a live model —
    /// the one part of this adapter with any logic in it (CLAUDE.md §7, "humble object").
    static func status(for availability: SystemLanguageModel.Availability) -> AIAvailabilityStatus {
        switch availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            .modelNotReady
        @unknown default:
            // A reason this build doesn't know about. Treating it as transient means the
            // user sees "still getting ready" and a retry rather than a dead end — the
            // safer default when the only alternative is a hard block on a condition we
            // cannot describe.
            .modelNotReady
        }
    }
}
