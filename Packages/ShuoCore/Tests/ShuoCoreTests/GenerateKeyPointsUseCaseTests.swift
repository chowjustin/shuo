//
//  GenerateKeyPointsUseCaseTests.swift
//  ShuoCoreTests
//

// The use case is a thin seam over the analyzer plus the normalizer; these tests verify
// the seam holds — that raw model output is always normalized before it escapes, and that
// a transcript covering nothing is a result rather than an error.

import Testing
import ShuoTestSupport
@testable import ShuoCore

@Suite("Generate key points use case")
struct GenerateKeyPointsUseCaseTests {

    private static let transcript = Transcript(original: "Some speech content here.")

    private var topical: SpeechPattern {
        guard let pattern = SpeechPatternCatalog.pattern(id: "inform.topical") else {
            preconditionFailure("inform.topical must exist in the catalog")
        }
        return pattern
    }

    @Test("Returns one key point per component of the requested pattern")
    func returnsCompleteSet() async throws {
        let analyzer = FakeSpeechAnalyzing(keyPoints: .fillAllComponents)
        let generate = GenerateKeyPointsUseCase(analyzer: analyzer)

        let result = try await generate(transcript: Self.transcript, pattern: topical)

        #expect(result.count == topical.components.count)
        #expect(result.map(\.componentID) == topical.components.map(\.id))
        #expect(result.allSatisfy { !$0.isAbsent })
    }

    @Test("Requests key points for the pattern it was given")
    func requestsCorrectPattern() async throws {
        let analyzer = FakeSpeechAnalyzing()
        let generate = GenerateKeyPointsUseCase(analyzer: analyzer)

        _ = try await generate(transcript: Self.transcript, pattern: topical)

        let calls = await analyzer.keyPointCalls
        #expect(calls == ["inform.topical"])
    }

    @Test("Unfilled components come back as '-' rather than missing")
    func fillsGapsWithAbsentMarker() async throws {
        let analyzer = FakeSpeechAnalyzing(
            keyPoints: .fillComponents(ids: ["topicOverview", "category1"])
        )
        let generate = GenerateKeyPointsUseCase(analyzer: analyzer)

        let result = try await generate(transcript: Self.transcript, pattern: topical)

        #expect(result.count == 5)
        #expect(result.filter(\.isAbsent).map(\.componentID)
            == ["category2", "category3", "closingSummary"])
        #expect(result.filter { !$0.isAbsent }.map(\.componentID)
            == ["topicOverview", "category1"])
    }

    @Test("A transcript covering nothing yields an all-absent set, not an error")
    func emptyCoverageIsNotAnError() async throws {
        // Genuinely useful output: it shows the speaker their draft is missing the whole
        // structure. Throwing here would hide that behind an error screen.
        let analyzer = FakeSpeechAnalyzing(keyPoints: .success([]))
        let generate = GenerateKeyPointsUseCase(analyzer: analyzer)

        let result = try await generate(transcript: Self.transcript, pattern: topical)

        #expect(result.count == topical.components.count)
        #expect(result.allSatisfy { $0.isAbsent })
    }

    @Test("Malformed model output is normalized before it escapes the use case")
    func normalizesMalformedOutput() async throws {
        // Out of order, a duplicate, and an invented component — all in one response.
        let analyzer = FakeSpeechAnalyzing(keyPoints: .success([
            KeyPoint(componentID: "closingSummary", componentName: "Closing Summary",
                     text: "Wrap up.", orderIndex: 99),
            KeyPoint(componentID: "category1", componentName: "Category 1",
                     text: "First.", orderIndex: 0),
            KeyPoint(componentID: "category1", componentName: "Category 1",
                     text: "Duplicate.", orderIndex: 0),
            KeyPoint(componentID: "invented", componentName: "Invented",
                     text: "Not real.", orderIndex: 7),
        ]))
        let generate = GenerateKeyPointsUseCase(analyzer: analyzer)

        let result = try await generate(transcript: Self.transcript, pattern: topical)

        #expect(result.map(\.componentID) == topical.components.map(\.id))
        #expect(result.map(\.orderIndex) == [0, 1, 2, 3, 4])
        #expect(result.first { $0.componentID == "category1" }?.text == "First.")
        #expect(!result.contains { $0.text == "Not real." })
    }

    @Test("Analyzer errors propagate unchanged")
    func propagatesAnalyzerErrors() async {
        let analyzer = FakeSpeechAnalyzing(keyPoints: .failure(.contextWindowExceeded))
        let generate = GenerateKeyPointsUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.contextWindowExceeded) {
            try await generate(transcript: Self.transcript, pattern: topical)
        }
    }
}
