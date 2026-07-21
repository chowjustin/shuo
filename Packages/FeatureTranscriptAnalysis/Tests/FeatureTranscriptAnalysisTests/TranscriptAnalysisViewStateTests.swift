//
//  TranscriptAnalysisViewStateTests.swift
//  FeatureTranscriptAnalysisTests
//

import Foundation
import ShuoCore
import Testing

@testable import FeatureTranscriptAnalysis

@Suite("Analysis toolbar layout")
struct TranscriptAnalysisViewStateTests {

    /// Every state the screen can be in. Hand-listed because the enum carries payloads and
    /// is not `CaseIterable`; the exhaustive switch in `toolbarLayout` is what forces a new
    /// state to be considered, and this list is the reminder to assert it here too.
    private static let allStates: [TranscriptAnalysisViewState] = [
        .analyzing,
        .waitingForModel,
        .unavailable(.appleIntelligenceNotEnabled),
        .unavailable(.deviceNotEligible),
        .unavailable(.modelNotReady),
        .rejected(.tooShort),
        .rejected(.mostlySilence),
        .rejected(.unintelligible),
        .rejected(.notASpeech),
        .failed(.aiGenerationFailed),
        .failed(.persistenceFailed),
        .loaded,
    ]

    @Test("only the loaded screen offers two buttons")
    func onlyLoadedOffersTwoButtons() {
        // This screen shipped twice with an unconditional ✕/✓ pair, so a spinner and every
        // error sheet carried a permanently-disabled ✓. Asserting the rule as a value is
        // what stops it coming back a third time.
        for state in Self.allStates where state != .loaded {
            #expect(state.toolbarLayout == .back, "\(state) should offer a single back button")
        }

        #expect(TranscriptAnalysisViewState.loaded.toolbarLayout == .leaveAndSave)
    }

    @Test("no waiting or failing state offers a save button")
    func nothingIncompleteOffersSave() {
        // Saving from a state with no analysis in it would persist an empty shell.
        let incomplete: [TranscriptAnalysisViewState] = [
            .analyzing, .waitingForModel,
            .unavailable(.modelNotReady), .rejected(.notASpeech), .failed(.aiGenerationFailed),
        ]

        for state in incomplete {
            #expect(state.toolbarLayout != .leaveAndSave, "\(state) must not offer save")
        }
    }
}
