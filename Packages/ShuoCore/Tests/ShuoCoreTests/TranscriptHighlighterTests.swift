//
//  TranscriptHighlighterTests.swift
//  ShuoCoreTests
//

import Foundation
@testable import ShuoCore
import Testing

@Suite("Transcript highlighter")
struct TranscriptHighlighterTests {
    private let highlighter = TranscriptHighlighter()

    private func keyPoint(_ text: String, id: String = "c") -> KeyPoint {
        KeyPoint(componentID: id, componentName: id, text: text, orderIndex: 0)
    }

    /// The substrings a set of ranges points at, for readable assertions.
    private func highlighted(_ text: String, _ ranges: [Range<Int>]) -> [String] {
        let characters = Array(text)
        return ranges.map { String(characters[$0]) }
    }

    @Test("A paraphrased sentence is matched even though the wording differs")
    func matchesParaphrase() {
        let refined = """
        We must migrate to a microservice architecture soon. The team lunch arrives at noon.
        """
        let point = keyPoint("Moving to microservices is now necessary for the architecture.")

        let ranges = highlighter.highlightRanges(in: refined, keyPoints: [point])

        let hits = highlighted(refined, ranges)
        #expect(hits.contains { $0.contains("microservice architecture") })
        #expect(!hits.contains { $0.contains("lunch") }, "an unrelated sentence must not be highlighted")
    }

    @Test("Ranges point at exactly the matched sentence, in order")
    func rangesAreWholeSentences() {
        let refined = "Alpha covers routing performance. Beta is about lunch. Gamma revisits routing performance again."
        let point = keyPoint("routing performance is the concern")

        let ranges = highlighter.highlightRanges(in: refined, keyPoints: [point])
        let hits = highlighted(refined, ranges)

        #expect(ranges == ranges.sorted { $0.lowerBound < $1.lowerBound })
        #expect(hits.allSatisfy { $0.contains("routing performance") })
        #expect(hits.count == 2)
    }

    @Test("A long key point still matches a shorter refined sentence that captures its gist")
    func longKeyPointMatchesShorterSentence() {
        let refined = """
        It was a complete mess, and I believe a modular monolith architecture would greatly \
        improve the system. The team lunch arrives at noon.
        """
        let point = keyPoint("""
        We definitely need to move to a modular monolith architecture soon because the driver \
        management system has been getting really slow lately.
        """)

        let ranges = highlighter.highlightRanges(in: refined, keyPoints: [point])
        let hits = highlighted(refined, ranges)

        #expect(hits.contains { $0.contains("modular monolith architecture") })
        #expect(!hits.contains { $0.contains("lunch") })
    }

    @Test("Absent key points contribute no highlights")
    func absentKeyPointsIgnored() {
        let refined = "This is a complete sentence about migration strategy."
        let absent = keyPoint(KeyPoint.absentText)

        let ranges = highlighter.highlightRanges(in: refined, keyPoints: [absent])

        #expect(ranges.isEmpty)
    }

    @Test("A single shared common word is not enough to highlight a sentence")
    func singleCommonWordDoesNotMatch() {
        let refined = "The engineering team shipped the release."
        let point = keyPoint("team morale and hiring plans for next quarter")

        let ranges = highlighter.highlightRanges(in: refined, keyPoints: [point])

        #expect(ranges.isEmpty)
    }

    @Test("Empty transcript yields no ranges")
    func emptyTranscript() {
        #expect(highlighter.highlightRanges(in: "", keyPoints: [keyPoint("anything here")]).isEmpty)
    }

    @Test("Offsets align with the string's character view for AttributedString mapping")
    func offsetsAreCharacterAccurate() throws {
        let refined = "Café talk about microservice migration today."
        let point = keyPoint("microservice migration plan")

        let ranges = highlighter.highlightRanges(in: refined, keyPoints: [point])
        let range = try #require(ranges.first)

        let characters = Array(refined)
        #expect(String(characters[range]).contains("microservice migration"))
    }
}
