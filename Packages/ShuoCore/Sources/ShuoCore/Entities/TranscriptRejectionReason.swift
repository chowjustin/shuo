//
//  TranscriptRejectionReason.swift
//  ShuoCore
//

// Why a transcript could not be analyzed as a speech script. Produced either by the
// zero-cost `TranscriptUsabilityPrecheck` or by the model's own usability verdict during
// classification, and surfaced to the user as an actionable message.

import Foundation

/// The reason a transcript was judged unusable as a speech script.
///
/// This is deliberately a small, closed set rather than a free-text explanation from the
/// model: the UI needs to map each case to specific, actionable copy ("we couldn't hear
/// any speech — try recording somewhere quieter"), and free text can't be localized,
/// tested, or trusted to stay on-message.
public enum TranscriptRejectionReason: String, Sendable, Equatable, Codable, CaseIterable {
    /// Fewer words than `TranscriptUsabilityPrecheck.Thresholds.minimumWordCount` — a stray
    /// tap, a one-line note, a truncated recording.
    ///
    /// **Measured, and only ever produced by the precheck.** Distinct from `tooShort`
    /// precisely so the UI can quote the number the check used, which it can only do when
    /// a number is what decided the verdict. See `modelReportable`.
    case tooFewWords
    /// Enough words to be worth reading, but not enough of a *speech* to structure — a
    /// paragraph of notes, an idea that never gets to its point.
    ///
    /// A judgement, not a measurement, and produced only by the model. The precheck runs
    /// first and unconditionally, so anything reaching the model has already cleared the
    /// word-count floor: telling this user a word count would name a bar they already
    /// passed.
    case tooShort
    /// Transcription produced filler or near-nothing: a silent or music-only recording.
    case mostlySilence
    /// Text that isn't coherent language — mistyped keys, mojibake, a file that was never
    /// speech to begin with.
    case unintelligible
    /// Readable, coherent text that simply isn't a speech or talk — a shopping list, code,
    /// an invoice, a chat log. The most common "wrong file attached" case.
    case notASpeech

    /// The reasons the *model* is allowed to report.
    ///
    /// `tooFewWords` is excluded because it is a measurement the precheck already made and
    /// the model cannot reliably repeat — letting it claim that verdict would put a
    /// specific number in front of a user that nothing actually counted. This is what the
    /// classification schema offers as candidates, so the model cannot emit the others by
    /// construction; `isModelReportable` is the belt-and-braces check on the way back in,
    /// since constrained decoding is a strong guarantee rather than an absolute one
    /// (CLAUDE.md §8).
    public static var modelReportable: [TranscriptRejectionReason] {
        allCases.filter(\.isModelReportable)
    }

    /// Whether the model may be the source of this verdict.
    public var isModelReportable: Bool {
        self != .tooFewWords
    }
}
