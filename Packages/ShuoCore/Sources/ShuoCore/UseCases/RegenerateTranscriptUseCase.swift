//
//  RegenerateTranscriptUseCase.swift
//  ShuoCore
//

// Step three of the analysis flow, and the only one the user triggers explicitly:
// rewrite the original transcript so it follows the selected pattern, anchored to the key
// points already on screen.

import Foundation

/// Produces the refined transcript for a pattern, on demand.
///
/// Deliberately explicit rather than automatic. Refinement is the most expensive call in
/// the flow and the one most likely to be regenerated repeatedly, so it runs only when
/// the user presses the button — not on every pattern switch, where it would burn time
/// and battery producing text the user may never scroll to.
///
/// `keyPoints` are passed in rather than re-derived so the rewrite is anchored to exactly
/// what the user has already been shown. Re-deriving them here would let the refined text
/// silently disagree with the key points displayed above it — a subtle, confusing bug.
public struct RegenerateTranscriptUseCase: Sendable {

    private let analyzer: any SpeechAnalyzing

    public init(analyzer: any SpeechAnalyzing) {
        self.analyzer = analyzer
    }

    /// - Returns: The refined transcript text, trimmed.
    /// - Throws: `ShuoError.aiGenerationFailed` when the model returns blank text — the
    ///   one case worth surfacing as retryable rather than storing an empty transcript
    ///   and leaving the user staring at nothing.
    public func callAsFunction(
        transcript: Transcript,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) async throws -> String {
        let refined = try await analyzer.refineTranscript(
            transcript.original,
            pattern: pattern,
            keyPoints: keyPoints
        )
        let trimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShuoError.aiGenerationFailed
        }
        return trimmed
    }
}
