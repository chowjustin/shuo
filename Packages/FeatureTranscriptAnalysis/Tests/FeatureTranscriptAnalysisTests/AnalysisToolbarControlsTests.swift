//
//  AnalysisToolbarControlsTests.swift
//  FeatureTranscriptAnalysisTests
//

import Foundation
import ShuoCore
import Testing

@testable import FeatureTranscriptAnalysis

@Suite("Analysis toolbar controls")
struct AnalysisToolbarControlsTests {

    /// Every state the screen can be in. Hand-listed because the enum carries payloads and
    /// is not `CaseIterable`; the exhaustive switch in the view is what forces a new state
    /// to be considered, and this list is the reminder to assert it here too.
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

    private static let incompleteStates: [TranscriptAnalysisViewState] = allStates.filter {
        $0 != .loaded
    }

    // MARK: - In the create flow

    @Test("‹ is always offered while there is an input step behind the screen")
    func backIsAlwaysOfferedInTheCreateFlow() {
        // Whatever the screen is doing, the recording and the modes that produced it are
        // still one step back, and going there is never the wrong thing to allow.
        for state in Self.allStates {
            let controls = AnalysisToolbarControls(state: state, canReturnToInput: true)
            #expect(controls.showsBack, "\(state) should offer a back button")
        }
    }

    @Test("only the loaded screen offers ✓ as well")
    func onlyLoadedOffersBoth() {
        // This screen shipped twice with an unconditional pair of buttons, so a spinner and
        // every error sheet carried a permanently-disabled one. Asserting the rule as a
        // value is what stops it coming back a third time.
        for state in Self.incompleteStates {
            let controls = AnalysisToolbarControls(state: state, canReturnToInput: true)
            #expect(!controls.showsFinish, "\(state) has nothing to finish")
        }

        let loaded = AnalysisToolbarControls(state: .loaded, canReturnToInput: true)
        #expect(loaded.showsBack)
        #expect(loaded.showsFinish)
    }

    // MARK: - Reopened from the library

    @Test("a reopened script offers ✓ alone — there is no earlier step to go back to")
    func reopenedScriptHidesBack() {
        let controls = AnalysisToolbarControls(state: .loaded, canReturnToInput: false)

        #expect(!controls.showsBack)
        #expect(controls.showsFinish)
    }

    @Test("a reopened script always keeps a way out, whatever the screen is doing")
    func reopenedScriptIsNeverTrapped() {
        // With no ‹, hiding ✓ on a spinner or an error sheet would leave the user on a
        // screen with no buttons at all. There it reads as "leave", and the
        // unsaved-changes prompt behind it covers the rest.
        for state in Self.allStates {
            let controls = AnalysisToolbarControls(state: state, canReturnToInput: false)
            #expect(controls.showsFinish, "\(state) must still offer a way out")
        }
    }

    @Test("no screen is ever left without a control")
    func everyScreenOffersSomething() {
        for state in Self.allStates {
            for canReturnToInput in [true, false] {
                let controls = AnalysisToolbarControls(
                    state: state,
                    canReturnToInput: canReturnToInput
                )
                #expect(
                    controls.showsBack || controls.showsFinish,
                    "\(state) with canReturnToInput: \(canReturnToInput) has no way out"
                )
            }
        }
    }
}
