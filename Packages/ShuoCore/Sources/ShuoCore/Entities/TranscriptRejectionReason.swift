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
    /// Too few words to structure — a stray tap, a one-line note, a truncated recording.
    case tooShort
    /// Transcription produced filler or near-nothing: a silent or music-only recording.
    case mostlySilence
    /// Text that isn't coherent language — mistyped keys, mojibake, a file that was never
    /// speech to begin with.
    case unintelligible
    /// Readable, coherent text that simply isn't a speech or talk — a shopping list, code,
    /// an invoice, a chat log. The most common "wrong file attached" case.
    case notASpeech
}
