//
//  GeneratedContentMapperTests.swift
//  ShuoAITests
//
//  Created by Justin Chow on 13/07/26.
//

// Swift Testing suite for `GeneratedContentMapper`, asserting model responses decode into
// `ShuoCore` domain entities — including the malformed and partial responses a small
// on-device model actually produces.
//
// `GeneratedContent(json:)` lets these run without a live model, so decoding gets real
// coverage even though the surrounding adapter does not.

import Foundation
import Testing
import FoundationModels
import ShuoCore
@testable import ShuoAI

@Suite("Generated content mapper")
struct GeneratedContentMapperTests {

    private func content(_ json: String) throws -> GeneratedContent {
        try GeneratedContent(json: json)
    }

    private var topical: SpeechPattern {
        guard let pattern = SpeechPatternCatalog.pattern(id: "inform.topical") else {
            preconditionFailure("inform.topical must exist in the catalog")
        }
        return pattern
    }

    // MARK: - Classification

    @Test("A usable classification decodes with its ranked ids in order")
    func decodesUsableClassification() throws {
        let result = try GeneratedContentMapper.classification(from: try content("""
            {
              "isUsable": true,
              "rankedPatternIDs": ["inform.topical", "inform.causeEffect"]
            }
            """))

        #expect(result.isUsable)
        #expect(result.rejectionReason == nil)
        #expect(result.rankedPatternIDs == ["inform.topical", "inform.causeEffect"])
    }

    @Test("A rejection decodes with its reason")
    func decodesRejection() throws {
        let result = try GeneratedContentMapper.classification(from: try content("""
            { "isUsable": false, "rejectionReason": "notASpeech", "rankedPatternIDs": [] }
            """))

        #expect(!result.isUsable)
        #expect(result.rejectionReason == .notASpeech)
        #expect(result.rankedPatternIDs.isEmpty)
    }

    @Test("A rejection with no reason still rejects, defaulting to notASpeech")
    func rejectionWithoutReason() throws {
        // An unusable verdict is still an unusable verdict; falling back to "usable"
        // because the reason was unreadable would push junk into the rest of the flow.
        let result = try GeneratedContentMapper.classification(from: try content("""
            { "isUsable": false, "rankedPatternIDs": [] }
            """))

        #expect(!result.isUsable)
        #expect(result.rejectionReason == .notASpeech)
    }

    @Test("A rejection with an unrecognized reason falls back to notASpeech")
    func rejectionWithUnknownReason() throws {
        let result = try GeneratedContentMapper.classification(from: try content("""
            { "isUsable": false, "rejectionReason": "vibes", "rankedPatternIDs": [] }
            """))

        #expect(!result.isUsable)
        #expect(result.rejectionReason == .notASpeech)
    }

    @Test("A usable classification with no ids decodes as an empty ranking")
    func usableWithMissingIDs() throws {
        // Left for `ClassifyTranscriptUseCase` to treat as a generation failure — the
        // mapper reports what came back rather than deciding what it means.
        let result = try GeneratedContentMapper.classification(from: try content("""
            { "isUsable": true }
            """))

        #expect(result.isUsable)
        #expect(result.rankedPatternIDs.isEmpty)
    }

    @Test("A response missing isUsable entirely is a generation failure")
    func missingIsUsableThrows() throws {
        // Wrong shape, not merely unexpected content — nothing sensible to default to.
        let malformed = try content(#"{ "rankedPatternIDs": ["inform.topical"] }"#)

        #expect(throws: ShuoError.aiGenerationFailed) {
            try GeneratedContentMapper.classification(from: malformed)
        }
    }

    // MARK: - Key points

    @Test("Key points decode against their pattern's components")
    func decodesKeyPoints() throws {
        let result = GeneratedContentMapper.keyPoints(
            from: try content("""
                {
                  "keyPoints": [
                    { "component": "Topic Overview", "content": "Remote work since 2020." },
                    { "component": "Category 1", "content": "Cost savings." }
                  ]
                }
                """),
            pattern: topical
        )

        #expect(result.count == 2)
        #expect(result[0].componentID == "topicOverview")
        #expect(result[0].text == "Remote work since 2020.")
        #expect(result[1].componentID == "category1")
    }

    @Test("Component matching tolerates case and punctuation drift")
    func keyPointMatchingIsLenient() throws {
        let result = GeneratedContentMapper.keyPoints(
            from: try content("""
                { "keyPoints": [ { "component": "closing summary:", "content": "Wrap up." } ] }
                """),
            pattern: topical
        )

        #expect(result.first?.componentID == "closingSummary")
    }

    @Test("Entries labelled with a component the pattern does not have are dropped")
    func dropsUnknownComponents() throws {
        // A `KeyPoint` carrying an unknown componentID would be meaningless downstream.
        let result = GeneratedContentMapper.keyPoints(
            from: try content("""
                {
                  "keyPoints": [
                    { "component": "Epilogue", "content": "Invented." },
                    { "component": "Category 2", "content": "Real." }
                  ]
                }
                """),
            pattern: topical
        )

        #expect(result.map(\.componentID) == ["category2"])
    }

    @Test("Decoded key points carry their component's order index")
    func keyPointsCarryOrder() throws {
        let result = GeneratedContentMapper.keyPoints(
            from: try content("""
                { "keyPoints": [ { "component": "Category 3", "content": "Third." } ] }
                """),
            pattern: topical
        )

        // Docs/SPEECH_PATTERNS.md §2.1 lists Category 3 fourth, so zero-based index 3.
        #expect(result.first?.orderIndex == 3)
    }

    @Test("An empty key point list decodes as no key points, not an error")
    func emptyKeyPointsIsNotAnError() throws {
        // The transcript covering nothing this pattern asks for is a real, informative
        // outcome — the normalizer turns it into an all-absent set.
        let result = GeneratedContentMapper.keyPoints(
            from: try content(#"{ "keyPoints": [] }"#),
            pattern: topical
        )

        #expect(result.isEmpty)
    }

    @Test("A response with no keyPoints field decodes as no key points")
    func missingKeyPointsFieldIsNotAnError() throws {
        let result = GeneratedContentMapper.keyPoints(
            from: try content("{}"),
            pattern: topical
        )

        #expect(result.isEmpty)
    }

    @Test("An entry with no content decodes as empty text for the normalizer to absorb")
    func missingContentBecomesEmptyText() throws {
        // `KeyPointNormalizer` treats empty text as absent, so this surfaces as "-".
        let result = GeneratedContentMapper.keyPoints(
            from: try content(#"{ "keyPoints": [ { "component": "Category 1" } ] }"#),
            pattern: topical
        )

        #expect(result.first?.text.isEmpty == true)
        #expect(KeyPointNormalizer().normalize(result, for: topical).allSatisfy { $0.isAbsent })
    }
}
