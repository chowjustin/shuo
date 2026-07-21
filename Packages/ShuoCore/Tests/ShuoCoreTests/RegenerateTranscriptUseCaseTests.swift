//
//  RegenerateTranscriptUseCaseTests.swift
//  ShuoCoreTests
//

// Refinement is user-triggered and the most expensive call in the flow, so the contract
// worth pinning down is narrow: it must be anchored to the key points already on screen,
// and it must never hand back blank text.

import Testing
import ShuoTestSupport
@testable import ShuoCore

@Suite("Regenerate transcript use case")
struct RegenerateTranscriptUseCaseTests {

    private static let transcript = Transcript(original: "Original speech content.")

    private var prep: SpeechPattern {
        guard let pattern = SpeechPatternCatalog.pattern(id: "persuade.prep") else {
            preconditionFailure("persuade.prep must exist in the catalog")
        }
        return pattern
    }

    private var keyPoints: [KeyPoint] {
        KeyPointNormalizer().normalize(
            [KeyPoint(componentID: "point", componentName: "Point",
                      text: "We should adopt a four-day week.", orderIndex: 0)],
            for: prep
        )
    }

    @Test("Returns the refined transcript for the selected pattern")
    func returnsRefinedText() async throws {
        let analyzer = FakeSpeechAnalyzing(refined: .success("Refined and restructured."))
        let regenerate = RegenerateTranscriptUseCase(analyzer: analyzer)

        let result = try await regenerate(
            transcript: Self.transcript,
            pattern: prep,
            keyPoints: keyPoints
        )

        #expect(result == "Refined and restructured.")
    }

    @Test("Refines against the pattern it was given")
    func usesGivenPattern() async throws {
        let analyzer = FakeSpeechAnalyzing()
        let regenerate = RegenerateTranscriptUseCase(analyzer: analyzer)

        _ = try await regenerate(
            transcript: Self.transcript,
            pattern: prep,
            keyPoints: keyPoints
        )

        let calls = await analyzer.refineCalls
        #expect(calls == ["persuade.prep"])
    }

    @Test("Refines from the original transcript, not a previously refined one")
    func refinesFromOriginal() async throws {
        // Refining a refinement compounds drift: each pass moves further from what the
        // speaker actually said. `Transcript.original` is the stable anchor.
        let analyzer = FakeSpeechAnalyzing(refined: .echoWithPatternName)
        let regenerate = RegenerateTranscriptUseCase(analyzer: analyzer)
        let alreadyRefined = Transcript(
            original: "Original speech content.",
            refined: "An earlier refinement."
        )

        let result = try await regenerate(
            transcript: alreadyRefined,
            pattern: prep,
            keyPoints: keyPoints
        )

        #expect(result.contains("Original speech content."))
        #expect(!result.contains("An earlier refinement."))
    }

    @Test("Surrounding whitespace is trimmed")
    func trimsWhitespace() async throws {
        let analyzer = FakeSpeechAnalyzing(refined: .success("\n  Refined text.  \n"))
        let regenerate = RegenerateTranscriptUseCase(analyzer: analyzer)

        let result = try await regenerate(
            transcript: Self.transcript,
            pattern: prep,
            keyPoints: keyPoints
        )

        #expect(result == "Refined text.")
    }

    @Test("Blank output is a retryable generation failure")
    func blankOutputThrows() async {
        let analyzer = FakeSpeechAnalyzing(refined: .success("   \n  "))
        let regenerate = RegenerateTranscriptUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.aiGenerationFailed) {
            try await regenerate(
                transcript: Self.transcript,
                pattern: prep,
                keyPoints: keyPoints
            )
        }
    }

    @Test("Analyzer errors propagate unchanged")
    func propagatesAnalyzerErrors() async {
        let analyzer = FakeSpeechAnalyzing(refined: .failure(.aiUnavailable))
        let regenerate = RegenerateTranscriptUseCase(analyzer: analyzer)

        await #expect(throws: ShuoError.aiUnavailable) {
            try await regenerate(
                transcript: Self.transcript,
                pattern: prep,
                keyPoints: keyPoints
            )
        }
    }
}
