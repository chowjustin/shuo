//
//  ContextWindowChunkerTests.swift
//  ShuoAITests
//
//  Created by Justin Chow on 13/07/26.
//

// Swift Testing suite for `ContextWindowChunker` — pure logic, fully unit-tested. See
// ARCHITECTURE.md §12.5. Getting this wrong means either a failed generation (budget too
// large) or silently dropped content (chunking bug), neither of which shows up in a
// manual test.

import Foundation
import Testing
@testable import ShuoAI

@Suite("Context window chunker")
struct ContextWindowChunkerTests {

    /// 100 distinct words, so a dropped or reordered chunk is detectable.
    private static let longTranscript = (0..<100)
        .map { "sentence\($0)" }
        .joined(separator: " ")

    // MARK: - Budget

    @Test("A short transcript needs no treatment at all")
    func shortTranscriptFits() {
        let chunker = ContextWindowChunker(budget: 1_000)

        #expect(!chunker.exceedsBudget("A brief speech."))
        #expect(chunker.condensed("A brief speech.") == "A brief speech.")
        #expect(chunker.chunks("A brief speech.") == ["A brief speech."])
    }

    @Test("The budget is derived from context size, minus room for instructions and output")
    func budgetDerivedFromContextSize() {
        let chunker = ContextWindowChunker(contextSize: 8_000)

        // (8000 - 1500 reserved) * 3.5 characters per token.
        #expect(chunker.budget == 22_750)
    }

    @Test("An implausibly small context size still yields a usable budget")
    func tinyContextSizeIsFloored() {
        // Guards against a zero or negative budget jamming the flow entirely.
        let chunker = ContextWindowChunker(contextSize: 100)

        #expect(chunker.budget > 0)
    }

    // MARK: - Condensing

    @Test("Condensing keeps the transcript within budget")
    func condensedRespectsBudget() {
        let chunker = ContextWindowChunker(budget: 200)

        #expect(chunker.condensed(Self.longTranscript).count <= 200)
    }

    @Test("Condensing keeps both the opening and the closing")
    func condensedKeepsBothEnds() {
        // The introduction states the topic and the conclusion states the takeaway — the
        // two parts that most reveal how a speech is organized.
        let chunker = ContextWindowChunker(budget: 200)

        let condensed = chunker.condensed(Self.longTranscript)

        #expect(condensed.hasPrefix("sentence0 "))
        #expect(condensed.hasSuffix("sentence99"))
    }

    @Test("The elided middle is marked in words, not left as a bare ellipsis")
    func condensedMarksTheElision() {
        // So the model reads it as a note about the text rather than as speech content.
        let chunker = ContextWindowChunker(budget: 200)

        #expect(chunker.condensed(Self.longTranscript).contains("omitted for length"))
    }

    // MARK: - Chunking

    @Test("Chunking a transcript that fits returns it as a single chunk")
    func chunkingShortTranscript() {
        let chunker = ContextWindowChunker(budget: 10_000)

        #expect(chunker.chunks(Self.longTranscript).count == 1)
    }

    @Test("Every chunk stays within budget")
    func chunksRespectBudget() {
        let chunker = ContextWindowChunker(budget: 100)

        let chunks = chunker.chunks(Self.longTranscript)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 100 })
    }

    @Test("Chunking preserves every word, in order, and splits none of them")
    func chunkingLosesNothing() {
        // The failure this guards against is silent: dropped or halved words would still
        // produce plausible-looking key points.
        let chunker = ContextWindowChunker(budget: 100)

        let rejoined = chunker.chunks(Self.longTranscript).joined(separator: " ")

        #expect(rejoined == Self.longTranscript)
    }

    @Test("A word longer than the entire budget is dropped rather than hard-split")
    func oversizedWordIsDropped() {
        // Cannot be language, cannot be placed, and hard-splitting it would corrupt it.
        // The real risk is a non-terminating loop, so this is a termination test.
        let chunker = ContextWindowChunker(budget: 20)
        let monster = String(repeating: "x", count: 500)

        let chunks = chunker.chunks("start \(monster) end")

        #expect(chunks.joined(separator: " ") == "start end")
    }

    @Test("Chunking never returns an empty list")
    func neverReturnsEmpty() {
        // A caller loops over the result; an empty list would silently skip generation.
        let chunker = ContextWindowChunker(budget: 5)

        #expect(!chunker.chunks("").isEmpty)
        #expect(!chunker.chunks("   ").isEmpty)
    }
}
