//
//  PatternClassification.swift
//  ShuoCore
//

// The single result of the classification pass: whether the transcript is usable at all,
// and if so, the ranked catalog ids of the best-matching patterns. One model call answers
// both questions — see `ClassifyTranscriptUseCase`.

import Foundation

/// The model's verdict on a transcript: usable or not, plus its ranked pattern choices.
///
/// Usability and ranking travel together because they come from one model call. Asking
/// separately would double the round trips on the happy path — and the judgement is the
/// same judgement: a model that can't find any pattern that fits is usually looking at
/// something that isn't a speech.
public struct PatternClassification: Sendable, Equatable {
    /// False when the transcript should not be structured at all. `rejectionReason` is
    /// then non-nil.
    public let isUsable: Bool
    /// Why the transcript was rejected. Non-nil if and only if `isUsable` is false — the
    /// initializer enforces that.
    public let rejectionReason: TranscriptRejectionReason?
    /// Catalog ids of the best-matching patterns, best first. Empty when `isUsable` is
    /// false. Callers must still validate these against `SpeechPatternCatalog` — this
    /// type carries whatever the model said, not a guarantee that the ids exist.
    public let rankedPatternIDs: [SpeechPattern.ID]

    /// A successful classification. `rankedPatternIDs` may still be empty if the model
    /// returned nothing usable; `ClassifyTranscriptUseCase` treats that as a rejection.
    public static func usable(rankedPatternIDs: [SpeechPattern.ID]) -> PatternClassification {
        PatternClassification(
            isUsable: true,
            rejectionReason: nil,
            rankedPatternIDs: rankedPatternIDs
        )
    }

    /// A rejection. Ranked ids are dropped — there is nothing to rank.
    public static func rejected(_ reason: TranscriptRejectionReason) -> PatternClassification {
        PatternClassification(
            isUsable: false,
            rejectionReason: reason,
            rankedPatternIDs: []
        )
    }

    private init(
        isUsable: Bool,
        rejectionReason: TranscriptRejectionReason?,
        rankedPatternIDs: [SpeechPattern.ID]
    ) {
        self.isUsable = isUsable
        self.rejectionReason = rejectionReason
        self.rankedPatternIDs = rankedPatternIDs
    }
}
