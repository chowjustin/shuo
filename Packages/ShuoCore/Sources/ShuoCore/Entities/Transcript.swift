//
//  Transcript.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// The text of a speech, in up to two forms.
///
/// `original` is what the user actually said or wrote — the verbatim transcription of a
/// recording or attachment, or typed text as-is. It is the input the on-device model
/// analyzes, and it never changes once captured.
///
/// `refined` is the model's restructured version. It stays nil until analysis has run,
/// which is why this type is useful before any AI is involved.
public struct Transcript: Sendable, Equatable, Codable {
    /// Verbatim text from the source. Never empty for a transcript that was produced
    /// successfully — an empty transcription is reported as `ShuoError.noSpeechDetected`
    /// rather than represented here.
    public let original: String
    /// The model's restructured text. Nil until analysis has run.
    public var refined: String?

    public init(original: String, refined: String? = nil) {
        self.original = original
        self.refined = refined
    }

    /// The text a caller should display or feed onward: the refined version when one
    /// exists, otherwise the original.
    public var effectiveText: String {
        refined ?? original
    }

    /// Rough word count of `original`, for length hints in the UI.
    public var originalWordCount: Int {
        original.split(whereSeparator: \.isWhitespace).count
    }
}
