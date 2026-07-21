//
//  AIAvailabilityGateTests.swift
//  ShuoAITests
//
//  Created by Justin Chow on 13/07/26.
//

// Covers the one piece of logic in the availability adapter: translating the framework's
// availability into the domain enum. The adapter itself is a humble object and needs no
// more than this (CLAUDE.md §7).

import Foundation
import Testing
import FoundationModels
import ShuoCore
@testable import ShuoAI

@Suite("AI availability gate")
struct AIAvailabilityGateTests {

    @Test("An available model reports available")
    func availableMapsThrough() {
        #expect(AIAvailabilityGate.status(for: .available) == .available)
    }

    @Test("Ineligible hardware is reported as such")
    func deviceNotEligible() {
        #expect(
            AIAvailabilityGate.status(for: .unavailable(.deviceNotEligible)) == .deviceNotEligible
        )
    }

    @Test("Apple Intelligence being switched off is actionable, not transient")
    func appleIntelligenceNotEnabled() {
        let status = AIAvailabilityGate.status(for: .unavailable(.appleIntelligenceNotEnabled))

        #expect(status == .appleIntelligenceNotEnabled)
        #expect(!status.isTransient, "the user must be told to act, not asked to wait")
    }

    @Test("A model still warming up is transient, so the UI waits rather than failing")
    func modelNotReadyIsTransient() {
        let status = AIAvailabilityGate.status(for: .unavailable(.modelNotReady))

        #expect(status == .modelNotReady)
        #expect(status.isTransient)
    }

    @Test("Only the available case counts as available")
    func onlyAvailableIsAvailable() {
        #expect(AIAvailabilityStatus.available.isAvailable)
        #expect(!AIAvailabilityStatus.modelNotReady.isAvailable)
        #expect(!AIAvailabilityStatus.deviceNotEligible.isAvailable)
        #expect(!AIAvailabilityStatus.appleIntelligenceNotEnabled.isAvailable)
    }
}
