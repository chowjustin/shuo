//
//  TranscriptUsabilityPrecheckTests.swift
//  ShuoCoreTests
//

// The precheck is the only thing standing between obviously-junk input and a multi-second
// model call, so both directions matter: it must reject the junk, and it must not reject
// ordinary speech.

import Testing
@testable import ShuoCore

@Suite("Transcript usability precheck")
struct TranscriptUsabilityPrecheckTests {

    private let precheck = TranscriptUsabilityPrecheck()

    /// ~60 words of unremarkable prose with normal punctuation — the control case.
    private static let realSpeech = """
        Good morning everyone. Today I want to talk about why remote work has reshaped \
        how our team collaborates. When we moved to a distributed model two years ago, \
        we assumed productivity would fall. It didn't. What actually changed was the \
        shape of our communication, and that turned out to matter far more than the \
        number of hours anyone logged at a desk.
        """

    @Test("Ordinary speech passes")
    func acceptsOrdinarySpeech() {
        #expect(precheck.reasonForRejection(Self.realSpeech) == nil)
    }

    @Test("Empty and whitespace-only text is too short")
    func rejectsEmpty() {
        #expect(precheck.reasonForRejection("") == .tooShort)
        #expect(precheck.reasonForRejection("   \n\t  ") == .tooShort)
    }

    @Test("A handful of words is too short")
    func rejectsShortText() {
        #expect(precheck.reasonForRejection("Just a quick note to self.") == .tooShort)
    }

    @Test("Punctuation alone does not count as words")
    func punctuationIsNotWords() {
        // Kept short so it stays below the alphanumeric-ratio sample size — this test is
        // about word tokenization, not the ratio check.
        #expect(precheck.reasonForRejection("... --- ,,,") == .tooShort)
    }

    @Test("Text right at the word-count floor passes")
    func boundaryAtMinimumWordCount() {
        let thresholds = TranscriptUsabilityPrecheck.Thresholds(minimumWordCount: 10)
        let precheck = TranscriptUsabilityPrecheck(thresholds: thresholds)
        let tenWords = "alpha bravo charlie delta echo foxtrot golf hotel india juliet"

        #expect(precheck.reasonForRejection(tenWords) == nil)
        #expect(
            precheck.reasonForRejection("alpha bravo charlie delta echo foxtrot golf hotel india")
                == .tooShort
        )
    }

    @Test("Below the ratio sample size, short junk reads as too short")
    func shortJunkIsTooShort() {
        #expect(precheck.reasonForRejection("#$%^&*") == .tooShort)
    }

    @Test("A long run of symbols is unintelligible, not merely short")
    func rejectsSymbolSoup() {
        // The misparsed-attachment case. Reporting "too short" for a 5 MB file that
        // parsed into garbage would be technically true and actively misleading, which is
        // why the ratio check runs before the word count.
        let garbage = String(repeating: "#$%^ &*()_ +={}[] |\\<>? ", count: 10)
        #expect(precheck.reasonForRejection(garbage) == .unintelligible)
    }

    @Test("Endlessly repeated filler reads as mostly silence")
    func rejectsRepetitiveFiller() {
        // What a recognizer produces from a near-silent recording: a few tokens, forever.
        let filler = String(repeating: "um uh um you know um ", count: 15)
        #expect(precheck.reasonForRejection(filler) == .mostlySilence)
    }

    @Test("Short repetitive text is not flagged as silence")
    func doesNotFlagShortRepetition() {
        // Below the sample-size floor the distinct-word ratio is meaningless, and applying
        // it anyway would reject legitimate short passages that repeat a keyword.
        let thresholds = TranscriptUsabilityPrecheck.Thresholds(
            minimumWordCount: 5,
            distinctWordRatioMinimumSampleSize: 100
        )
        let precheck = TranscriptUsabilityPrecheck(thresholds: thresholds)
        let repetitive = String(repeating: "growth growth growth ", count: 5)

        #expect(precheck.reasonForRejection(repetitive) == nil)
    }

    @Test("Speech with statistics and numbers is not rejected")
    func acceptsNumbers() {
        // Digits count as alphanumeric — a data-heavy talk must not read as symbol soup.
        let statistical = """
            Revenue grew 42 percent in 2024, from 18.6 million to 26.4 million dollars. \
            Headcount rose from 120 to 145 people over the same period, which means \
            revenue per employee climbed roughly 17 percent year over year across all \
            three regions we operate in today.
            """
        #expect(precheck.reasonForRejection(statistical) == nil)
    }

    @Test("The precheck never claims something is not a speech")
    func neverReturnsNotASpeech() {
        // Deciding a coherent shopping list isn't a talk requires comprehension. The
        // precheck must defer that to the model rather than guess.
        let shoppingList = """
            Milk, eggs, bread, butter, two onions, a bag of rice, chicken thighs, olive \
            oil, coffee beans, paper towels, dish soap, toothpaste, bananas, spinach, \
            yogurt, cheddar cheese, tomatoes, garlic, lemons, and a bar of chocolate.
            """
        #expect(precheck.reasonForRejection(shoppingList) == nil)
    }
}
