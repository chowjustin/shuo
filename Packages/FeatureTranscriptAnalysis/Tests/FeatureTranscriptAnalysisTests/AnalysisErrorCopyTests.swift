//
//  AnalysisErrorCopyTests.swift
//  FeatureTranscriptAnalysisTests
//
//  Created by Justin Chow on 21/07/26.
//

import ShuoCore
import Testing

@testable import FeatureTranscriptAnalysis

@Suite("AnalysisErrorCopy")
struct AnalysisErrorCopyTests {

    @Test("every rejection reason gets its own wording, never a shared fallback")
    func rejectionReasonsAreDistinct() {
        let titles = TranscriptRejectionReason.allCases.map { AnalysisErrorCopy(reason: $0).title }

        #expect(Set(titles).count == titles.count)
    }

    @Test("a rejection arriving as an error reuses the same wording as the rejected state")
    func rejectionAsErrorMatchesRejectionCopy() {
        for reason in TranscriptRejectionReason.allCases {
            let viaError = AnalysisErrorCopy(error: .transcriptNotUsable(reason))

            #expect(viaError == AnalysisErrorCopy(reason: reason))
        }
    }

    // MARK: - Availability

    /// Every status, since `AIAvailabilityStatus` is not `CaseIterable`. Adding a case
    /// without adding it here is the one gap this list can't catch, but the initializer's
    /// exhaustive switch does.
    private static let allStatuses: [AIAvailabilityStatus] = [
        .available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
    ]

    @Test("every availability status gets its own wording, never a shared fallback")
    func availabilityStatusesAreDistinct() {
        let copies = Self.allStatuses.map { AnalysisErrorCopy(availability: $0) }

        #expect(Set(copies.map(\.title)).count == copies.count)
        #expect(Set(copies.map(\.message)).count == copies.count)
        #expect(Set(copies.map(\.systemImage)).count == copies.count)
    }

    @Test("no availability status renders a blank sheet")
    func everyAvailabilityStatusHasCopy() {
        for status in Self.allStatuses {
            let copy = AnalysisErrorCopy(availability: status)

            #expect(!copy.systemImage.isEmpty)
            #expect(!copy.title.isEmpty)
            #expect(!copy.message.isEmpty)
        }
    }

    @Test("Apple Intelligence switched off points at Settings and offers no in-app retry")
    func appleIntelligenceOffPointsAtSettings() {
        let copy = AnalysisErrorCopy(availability: .appleIntelligenceNotEnabled)

        #expect(copy.systemImage == "sparkles.slash")
        #expect(copy.title == "Apple Intelligence is turned off.")
        #expect(copy.message.contains("Settings"))
        // Nothing in the app can flip that switch, so a confirm button would fail every
        // time it was pressed.
    }

    @Test("ineligible hardware says so plainly, without implying a fix")
    func deviceNotEligibleImpliesNoFix() {
        let copy = AnalysisErrorCopy(availability: .deviceNotEligible)

        #expect(copy.systemImage == "iphone.slash")
        #expect(copy.title == "This device can't run Shuo's analysis.")
        // v1 requires eligible hardware and has no degraded mode (ARCHITECTURE.md §2.1);
        // sending this user to Settings would be a wild goose chase.
        #expect(!copy.message.contains("Settings"))
    }

    @Test("a model still warming up is not phrased as something the user must fix")
    func modelNotReadyReadsAsAWait() {
        // Normally rendered as `LoadingView`, not this sheet — but if it ever surfaces here
        // it must still read as a wait rather than an instruction.
        let copy = AnalysisErrorCopy(availability: .modelNotReady)

        #expect(!copy.message.contains("Settings"))
    }

    @Test("availability copy is not just the aiUnavailable error copy under another name")
    func availabilityCopyDiffersFromTheGenericError() {
        // `ShuoError.aiUnavailable` carries no payload, which is the whole reason this
        // second initializer exists.
        let generic = AnalysisErrorCopy(error: .aiUnavailable)

        #expect(AnalysisErrorCopy(availability: .deviceNotEligible) != generic)
        #expect(AnalysisErrorCopy(availability: .modelNotReady) != generic)
    }

    @Test("every case produces non-empty copy, so no state can render a blank sheet")
    func everyCaseHasCopy() {
        let errors: [ShuoError] = [
            .aiUnavailable, .contextWindowExceeded, .aiGenerationFailed, .persistenceFailed,
            .transcriptionFailed, .importFailed, .recordingFailed,
        ]

        for error in errors {
            let copy = AnalysisErrorCopy(error: error)

            #expect(!copy.systemImage.isEmpty)
            #expect(!copy.title.isEmpty)
            #expect(!copy.message.isEmpty)
        }
    }
    // MARK: - Copy is the only channel now

    @Test("errors reachable on this screen each read differently")
    func reachableErrorsReadDifferently() {
        // The screen offers a single back button, so wording is the only thing telling the
        // user what happened. Non-emptiness alone would pass against one shared placeholder.
        let reachable: [ShuoError] = [
            .aiUnavailable, .contextWindowExceeded, .aiGenerationFailed, .persistenceFailed,
        ]
        let messages = Set(reachable.map { AnalysisErrorCopy(error: $0).message })

        #expect(messages.count == reachable.count, "two reachable errors share a message")
    }

    @Test("no copy promises an action the single back button cannot perform")
    func noCopyPromisesAButtonThatIsNotThere() {
        // The ✓ that used to offer "Try again" is gone: every non-loaded state has one ‹
        // back to input. Copy inviting a tap on a button that no longer exists would send
        // the user looking for it.
        let phrases = ["tap try again", "press try again", "tap retry", "use the button below"]
        let allCopy: [AnalysisErrorCopy] =
            [.tooShort, .mostlySilence, .unintelligible, .notASpeech].map(AnalysisErrorCopy.init(reason:))
            + [.appleIntelligenceNotEnabled, .deviceNotEligible, .modelNotReady, .available]
                .map(AnalysisErrorCopy.init(availability:))
            + [ShuoError.aiUnavailable, .contextWindowExceeded, .aiGenerationFailed, .persistenceFailed]
                .map(AnalysisErrorCopy.init(error:))

        for copy in allCopy {
            let text = "\(copy.title) \(copy.message)".lowercased()
            for phrase in phrases {
                #expect(!text.contains(phrase), "copy points at a button that no longer exists")
            }
        }
    }

    @Test("every rejection reason reads differently, so the verdict is specific")
    func rejectionReasonsReadDifferently() {
        let reasons: [TranscriptRejectionReason] = [.tooShort, .mostlySilence, .unintelligible, .notASpeech]
        let messages = Set(reasons.map { AnalysisErrorCopy(reason: $0).message })

        #expect(messages.count == reasons.count, "two rejection reasons share a message")
    }

}
