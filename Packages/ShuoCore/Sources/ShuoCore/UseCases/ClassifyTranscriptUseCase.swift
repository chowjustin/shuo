//
//  ClassifyTranscriptUseCase.swift
//  ShuoCore
//

// Step one of the analysis flow: decide whether the transcript is a usable speech script
// and, if so, which catalog patterns fit it best. Classifies against a fixed catalog
// rather than letting the model free-generate patterns — see `SpeechPattern` for why.

import Foundation

/// Judges a transcript and returns the best-matching patterns for the chosen purpose,
/// best first.
///
/// Two guards bracket the model call, and both matter:
///
/// - **Before:** `TranscriptUsabilityPrecheck` rejects mechanically unusable input for
///   free, so a stray tap or a silent recording fails instantly instead of after seconds
///   of generation.
/// - **After:** every id the model returns is validated against the *candidate* set, not
///   merely the catalog. A hallucinated id, or a real id belonging to another purpose,
///   is discarded rather than propagated — so nothing downstream ever has to wonder
///   whether a `SpeechPattern` it holds is real.
public struct ClassifyTranscriptUseCase: Sendable {

    /// The number of suggestions the UI shows. Enforced here rather than trusted from the
    /// model: guided generation constrains shape well but count only loosely, and this is
    /// a one-line clamp.
    public static let suggestionCount = 3

    private let analyzer: any SpeechAnalyzing
    private let precheck: TranscriptUsabilityPrecheck
    private let maximumSuggestions: Int

    public init(
        analyzer: any SpeechAnalyzing,
        precheck: TranscriptUsabilityPrecheck = TranscriptUsabilityPrecheck(),
        maximumSuggestions: Int = ClassifyTranscriptUseCase.suggestionCount
    ) {
        self.analyzer = analyzer
        self.precheck = precheck
        self.maximumSuggestions = maximumSuggestions
    }

    /// - Returns: Up to `maximumSuggestions` patterns, ranked best-first, all belonging to
    ///   `purpose`.
    /// - Throws: `ShuoError.transcriptNotUsable` when the transcript isn't a speech
    ///   script — from the precheck or from the model's own verdict.
    ///   `ShuoError.aiGenerationFailed` when the model reported the transcript usable but
    ///   returned no id this app recognizes, which is a generation failure rather than a
    ///   judgement about the user's content.
    public func callAsFunction(
        transcript: Transcript,
        purpose: SpeechPurpose
    ) async throws -> [SpeechPattern] {
        if let reason = precheck.reasonForRejection(transcript.original) {
            throw ShuoError.transcriptNotUsable(reason)
        }

        let candidates = SpeechPatternCatalog.patterns(for: purpose)
        let classification = try await analyzer.classify(
            transcript: transcript.original,
            purpose: purpose,
            candidates: candidates
        )

        guard classification.isUsable else {
            // A model that reports "unusable" without saying why is still reporting
            // unusable; `.notASpeech` is the broadest honest reading of that.
            throw ShuoError.transcriptNotUsable(classification.rejectionReason ?? .notASpeech)
        }

        let ranked = resolve(classification.rankedPatternIDs, within: candidates)
        guard !ranked.isEmpty else {
            throw ShuoError.aiGenerationFailed
        }
        return Array(ranked.prefix(maximumSuggestions))
    }

    /// Maps ids to candidate patterns, preserving the model's ranking, dropping anything
    /// not in `candidates`, and collapsing duplicates to their first occurrence.
    private func resolve(
        _ ids: [SpeechPattern.ID],
        within candidates: [SpeechPattern]
    ) -> [SpeechPattern] {
        let byID = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<SpeechPattern.ID>()
        return ids.compactMap { id in
            guard let pattern = byID[id], seen.insert(id).inserted else { return nil }
            return pattern
        }
    }
}
