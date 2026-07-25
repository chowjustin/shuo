//
//  TranscriptHighlighter.swift
//  ShuoCore
//

import Foundation

/// Finds the parts of a refined transcript that convey each key point, so the UI can highlight them.
public struct TranscriptHighlighter: Sendable {

    /// How much a sentence and a key point must overlap to match, scored as the overlap coefficient.
    private let minimumScore: Double

    /// The absolute number of shared keywords required regardless of score.
    private let minimumOverlap: Int

    /// A key point needs at least this many meaningful keywords to be matchable at all.
    private let minimumKeywords: Int

    public init(minimumScore: Double = 0.3, minimumOverlap: Int = 2, minimumKeywords: Int = 2) {
        self.minimumScore = minimumScore
        self.minimumOverlap = minimumOverlap
        self.minimumKeywords = minimumKeywords
    }

    /// Character-offset ranges within `refined` that convey `keyPoints`.
    public func highlightRanges(in refined: String, keyPoints: [KeyPoint]) -> [Range<Int>] {
        guard !refined.isEmpty else { return [] }

        let keywordSets = keyPoints
            .filter { !$0.isAbsent }
            .map { Self.keywords(from: $0.text) }
            .filter { $0.count >= minimumKeywords }
        guard !keywordSets.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        for sentence in Self.sentences(in: refined) {
            let sentenceWords = Self.keywords(from: sentence.text)
            guard !sentenceWords.isEmpty else { continue }

            let matches = keywordSets.contains { keywords in
                let overlap = keywords.intersection(sentenceWords).count
                guard overlap >= minimumOverlap else { return false }
                let score = Double(overlap) / Double(min(keywords.count, sentenceWords.count))
                return score >= minimumScore
            }
            if matches { ranges.append(sentence.range) }
        }
        return ranges
    }

    // MARK: - Sentences

    private struct Sentence {
        let text: String
        /// Character-offset range within the source string, leading whitespace trimmed.
        let range: Range<Int>
    }

    /// Splits `text` into sentences with their character-offset ranges.
    private static func sentences(in text: String) -> [Sentence] {
        let characters = Array(text)
        let count = characters.count
        var sentences: [Sentence] = []
        var i = 0

        while i < count {
            while i < count, characters[i].isWhitespace { i += 1 }
            guard i < count else { break }

            let start = i
            while i < count, !Self.isTerminator(characters[i]) { i += 1 }
            while i < count, Self.isTerminator(characters[i]) { i += 1 }
            let end = i

            let slice = String(characters[start..<end])
            if !slice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(Sentence(text: slice, range: start..<end))
            }
        }
        return sentences
    }

    private static func isTerminator(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
    }

    // MARK: - Keywords

    /// The meaningful words of a string: lowercased, longer than three characters, and not a common function word.
    private static func keywords(from text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 3 && !stopWords.contains($0) }
                .map(stem)
        )
    }

    /// Cheap plural folding so a key point's wording still matches the rewrite's.
    private static func stem(_ word: String) -> String {
        guard word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    /// Long-enough words that still carry no topic signal.
    private static let stopWords: Set<String> = [
        "that", "this", "these", "those", "with", "have", "has", "had", "will", "would",
        "could", "should", "been", "being", "were", "your", "yours", "they", "them", "their",
        "then", "than", "there", "here", "what", "when", "where", "which", "while", "into",
        "from", "just", "like", "very", "really", "actually", "going", "gonna", "want",
        "wanted", "about", "because", "some", "such", "only", "also", "even", "much", "many",
        "more", "most", "over", "under", "back", "make", "made", "need", "needs", "sure",
        "okay", "yeah", "kind", "sort", "stuff", "thing", "things", "lets", "gotta", "them",
    ]
}
