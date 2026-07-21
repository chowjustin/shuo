//
//  ClassifyTranscriptUseCaseTests.swift
//  ShuoCoreTests
//

// Classification is where untrusted model output first meets the domain, so most of these
// tests are about what happens when the model misbehaves — wrong purpose, unknown ids,
// duplicates, too many results, a usable verdict with nothing usable in it.

import Testing
import ShuoTestSupport
@testable import ShuoCore

@Suite("Classify transcript use case")
struct ClassifyTranscriptUseCaseTests {

    /// Comfortably past the precheck's floors, so these tests exercise the model path.
    private static let validTranscript = Transcript(original: """
        Good morning everyone. Today I want to talk about why remote work has reshaped \
        how our team collaborates. When we moved to a distributed model two years ago, \
        we assumed productivity would fall. It didn't. What actually changed was the \
        shape of our communication, and that turned out to matter far more than the \
        number of hours anyone logged at a desk each week.
        """)

    // MARK: - Happy path

    @Test("Returns the model's ranked patterns, best first")
    func returnsRankedPatterns() async throws {
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: [
                "inform.causeEffect", "inform.topical", "inform.chronological",
            ]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        let result = try await classify(transcript: Self.validTranscript, purpose: .inform)

        #expect(result.map(\.id) == [
            "inform.causeEffect", "inform.topical", "inform.chronological",
        ])
    }

    @Test("Hands the model only the candidates for the chosen purpose")
    func passesPurposeScopedCandidates() async throws {
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: ["persuade.prep"]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        _ = try await classify(transcript: Self.validTranscript, purpose: .persuade)

        let call = try #require(await analyzer.classifyCalls.first)
        #expect(call.purpose == .persuade)
        #expect(call.candidateIDs.count == 7)
        #expect(call.candidateIDs.allSatisfy { $0.hasPrefix("persuade.") })
    }

    @Test("Clamps to three suggestions even when the model returns more")
    func clampsToThree() async throws {
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: [
                "inform.topical", "inform.chronological", "inform.causeEffect",
                "inform.spatial", "inform.definition",
            ]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        let result = try await classify(transcript: Self.validTranscript, purpose: .inform)

        #expect(result.count == 3)
        #expect(result.map(\.id) == [
            "inform.topical", "inform.chronological", "inform.causeEffect",
        ])
    }

    @Test("Fewer than three suggestions is acceptable")
    func allowsFewerThanThree() async throws {
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: ["inspire.herosJourney"]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        let result = try await classify(transcript: Self.validTranscript, purpose: .inspire)

        #expect(result.map(\.id) == ["inspire.herosJourney"])
    }

    // MARK: - Untrusted model output

    @Test("Ids that are not in the catalog are discarded")
    func discardsUnknownIDs() async throws {
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: [
                "inform.invented", "inform.topical", "totally made up",
            ]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        let result = try await classify(transcript: Self.validTranscript, purpose: .inform)

        #expect(result.map(\.id) == ["inform.topical"])
    }

    @Test("A real id belonging to another purpose is discarded")
    func discardsOutOfPurposeIDs() async throws {
        // The sharp case: `persuade.prep` is a perfectly real pattern, just not one the
        // user asked for. Validating against the catalog alone would let it through.
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: [
                "persuade.prep", "inform.topical",
            ]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        let result = try await classify(transcript: Self.validTranscript, purpose: .inform)

        #expect(result.map(\.id) == ["inform.topical"])
    }

    @Test("Duplicate ids collapse to a single suggestion")
    func collapsesDuplicates() async throws {
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: [
                "inform.topical", "inform.topical", "inform.spatial",
            ]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        let result = try await classify(transcript: Self.validTranscript, purpose: .inform)

        #expect(result.map(\.id) == ["inform.topical", "inform.spatial"])
    }

    @Test("A usable verdict with no recognizable id is a generation failure")
    func usableWithNoValidIDsFails() async {
        // Not `.transcriptNotUsable` — the model said the transcript was fine, so blaming
        // the user's content would be wrong. This is the app's failure, and retryable.
        let analyzer = FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: ["nonsense"]))
        )
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.aiGenerationFailed) {
            try await classify(transcript: Self.validTranscript, purpose: .inform)
        }
    }

    // MARK: - Rejection

    @Test("The precheck rejects short input without calling the model at all")
    func precheckShortCircuitsBeforeTheModel() async {
        let analyzer = FakeSpeechAnalyzing()
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.transcriptNotUsable(.tooShort)) {
            try await classify(transcript: Transcript(original: "hi"), purpose: .inform)
        }

        let callCount = await analyzer.classifyCallCount
        #expect(callCount == 0, "the model must not be invoked for obviously unusable input")
    }

    @Test("The model's rejection is surfaced with its reason")
    func surfacesModelRejection() async {
        let analyzer = FakeSpeechAnalyzing(classification: .success(.rejected(.notASpeech)))
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.transcriptNotUsable(.notASpeech)) {
            try await classify(transcript: Self.validTranscript, purpose: .inform)
        }
    }

    @Test("Analyzer errors propagate unchanged")
    func propagatesAnalyzerErrors() async {
        let analyzer = FakeSpeechAnalyzing(classification: .failure(.aiUnavailable))
        let classify = ClassifyTranscriptUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.aiUnavailable) {
            try await classify(transcript: Self.validTranscript, purpose: .inform)
        }
    }
}
