//
//  TranscriptUsabilityPrecheck.swift
//  ShuoCore
//

// Zero-cost first filter on transcript usability. Runs before any model call so obviously
// unusable input — empty, near-empty, symbol soup, endless repetition — fails instantly
// instead of after a multi-second generation. Pure and deterministic; the semantic
// judgement ("is this a speech at all?") is the model's job, not this type's.

import Foundation

/// Rejects transcripts that are structurally unusable, without invoking the model.
///
/// This is a *cheap filter, not a complete one*. It catches the mechanical failures — a
/// stray tap, a silent recording, a binary file read as text — where spending seconds of
/// on-device generation to reach the same conclusion would be pure waste. Anything that
/// reads as plausible language passes through to the model, which is the only thing that
/// can judge whether plausible language is actually a *speech*.
///
/// Consequently `reasonForRejection` never returns `.notASpeech`: distinguishing a talk
/// from a shopping list needs comprehension. That case only ever comes back from
/// classification.
public struct TranscriptUsabilityPrecheck: Sendable {

    /// Tuning knobs, exposed so tests can drive edge cases without depending on the
    /// shipped values — and so the values themselves stay reviewable in one place rather
    /// than scattered as magic numbers through the checks.
    public struct Thresholds: Sendable {
        /// Below this many words there is not enough material to fill even a
        /// three-component pattern. Roughly ten seconds of speech.
        public var minimumWordCount: Int
        /// Minimum share of non-whitespace characters that must be letters or digits.
        /// Ordinary prose sits around 0.85–0.92 once punctuation is counted against it;
        /// symbol soup and mojibake fall far below.
        public var minimumAlphanumericRatio: Double
        /// Minimum share of words that must be distinct. Filler-only transcriptions
        /// ("um, um, you know, um") and stuck-loop recognizer output collapse here.
        public var minimumDistinctWordRatio: Double
        /// The distinct-word check only applies above this length. Short passages
        /// legitimately repeat words, so applying it to them produces false rejections.
        public var distinctWordRatioMinimumSampleSize: Int
        /// The alphanumeric-ratio check only applies once there are at least this many
        /// non-whitespace characters. Below it, "too short" is both true and more useful
        /// than "unintelligible".
        public var alphanumericRatioMinimumSampleSize: Int

        public init(
            minimumWordCount: Int = 25,
            minimumAlphanumericRatio: Double = 0.75,
            minimumDistinctWordRatio: Double = 0.25,
            distinctWordRatioMinimumSampleSize: Int = 40,
            alphanumericRatioMinimumSampleSize: Int = 40
        ) {
            self.minimumWordCount = minimumWordCount
            self.minimumAlphanumericRatio = minimumAlphanumericRatio
            self.minimumDistinctWordRatio = minimumDistinctWordRatio
            self.distinctWordRatioMinimumSampleSize = distinctWordRatioMinimumSampleSize
            self.alphanumericRatioMinimumSampleSize = alphanumericRatioMinimumSampleSize
        }
    }

    private let thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// The reason `transcript` is unusable, or nil when it should go on to the model.
    ///
    /// The alphanumeric check runs *before* the word-count check, and the ordering is
    /// deliberate. A file that parsed into symbol soup contains no word tokens at all, so
    /// a word-count-first order would report it as "too short" — technically true, and
    /// actively misleading to someone who just attached a 5 MB document. Substantial
    /// content that isn't language should say so.
    public func reasonForRejection(_ transcript: String) -> TranscriptRejectionReason? {
        let (alphanumeric, nonWhitespace) = characterCounts(of: transcript)

        if nonWhitespace >= thresholds.alphanumericRatioMinimumSampleSize {
            let ratio = Double(alphanumeric) / Double(nonWhitespace)
            if ratio < thresholds.minimumAlphanumericRatio {
                return .unintelligible
            }
        }

        let words = Self.words(in: transcript)

        guard words.count >= thresholds.minimumWordCount else {
            return .tooShort
        }

        if words.count >= thresholds.distinctWordRatioMinimumSampleSize {
            let distinct = Set(words.map { $0.lowercased() }).count
            let ratio = Double(distinct) / Double(words.count)
            if ratio < thresholds.minimumDistinctWordRatio {
                return .mostlySilence
            }
        }

        return nil
    }

    /// Whitespace-separated tokens that contain at least one letter or digit, so stray
    /// punctuation ("—", "...") is not counted as a word.
    static func words(in transcript: String) -> [Substring] {
        transcript
            .split(whereSeparator: \.isWhitespace)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
    }

    /// Counts letters-or-digits and non-whitespace characters in one pass. Returned as a
    /// pair rather than a ratio so the caller can gate on the sample size before dividing.
    private func characterCounts(of transcript: String) -> (alphanumeric: Int, nonWhitespace: Int) {
        var alphanumeric = 0
        var nonWhitespace = 0
        for character in transcript where !character.isWhitespace {
            nonWhitespace += 1
            if character.isLetter || character.isNumber {
                alphanumeric += 1
            }
        }
        return (alphanumeric, nonWhitespace)
    }
}
