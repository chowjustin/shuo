//
//  GrammarSuggestion.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `GrammarSuggestion` struct (originalPhrase, suggestedPhrase,
// explanation). Defined now so the persisted schema and `SpeechAnalyzing` protocol
// don't need a breaking change later, but unused in v1 — do not wire this into any use
// case or ViewModel unless explicitly asked to pick that work back up (CLAUDE.md §8, §11).

import Foundation

/// One proposed wording improvement for a phrase in a transcript.
///
/// Declared so `SpeechAnalyzing.analyzeGrammar` and the persisted `Script` schema have a
/// stable shape, and adding the feature later is additive rather than a migration.
/// Nothing in v1 produces or consumes these.
public struct GrammarSuggestion: Sendable, Identifiable, Equatable, Codable, Hashable {
    /// Identity is the original phrase — suggestions are keyed by what they replace, and
    /// there is at most one suggestion per phrase.
    public var id: String { originalPhrase }

    /// The phrase as the speaker said it, verbatim, so it can be located in the transcript
    /// by substring match. Stored as a snippet rather than a character range because
    /// ranges break the moment the transcript is edited (ARCHITECTURE.md §3.2.2).
    public let originalPhrase: String
    /// The proposed replacement.
    public let suggestedPhrase: String
    /// Why the change helps, in one sentence, for display under the suggestion.
    public let explanation: String

    public init(originalPhrase: String, suggestedPhrase: String, explanation: String) {
        self.originalPhrase = originalPhrase
        self.suggestedPhrase = suggestedPhrase
        self.explanation = explanation
    }
}
