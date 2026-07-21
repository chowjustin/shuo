//
//  Script.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `Script` — the aggregate root persisted for a finished speech (title,
// purpose, transcript, patterns, key points, grammar suggestions, timestamps). Captures
// the full generated state, not just the raw transcript, so reopening a script needs no
// AI re-invocation. See ARCHITECTURE.md §3.3.

import Foundation

/// A saved speech: everything the user produced and everything the model generated for it.
///
/// The whole generated state is persisted, not just the transcript, because "previously
/// generated data remains available" means reopening must be instant and offline —
/// re-running classification and extraction on open would cost seconds and could produce
/// *different* results than the user saw when they saved.
///
/// Patterns are stored as **catalog ids, not copies**. The catalog is fixed app data; a
/// denormalized copy of a pattern's name and components would go stale the moment that
/// wording is improved, leaving old scripts rendering outdated structure. `keyPoints` are
/// stored in full because they are genuinely per-script content.
public struct Script: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public var title: String
    public let purpose: SpeechPurpose
    /// The original transcript, plus the refined version if the user regenerated one.
    public var transcript: Transcript
    /// Catalog ids of the patterns suggested for this script, best first. Resolve with
    /// `suggestedPatterns`.
    public var suggestedPatternIDs: [SpeechPattern.ID]
    /// The pattern the key points and refined transcript belong to. Nil only for a script
    /// saved before a pattern was chosen.
    public var selectedPatternID: SpeechPattern.ID?
    /// Key points for `selectedPatternID`, one per component of that pattern.
    public var keyPoints: [KeyPoint]
    /// Reserved for the deferred grammar feature (CLAUDE.md §8, §11). Always empty in v1;
    /// present so adding that feature later is additive rather than a schema migration.
    public var grammarSuggestions: [GrammarSuggestion]
    /// Duration of the source recording, when the script came from audio or video. Nil for
    /// typed input. Shown on the Home list.
    public var recordingDuration: TimeInterval?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        purpose: SpeechPurpose,
        transcript: Transcript,
        suggestedPatternIDs: [SpeechPattern.ID] = [],
        selectedPatternID: SpeechPattern.ID? = nil,
        keyPoints: [KeyPoint] = [],
        grammarSuggestions: [GrammarSuggestion] = [],
        recordingDuration: TimeInterval? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.transcript = transcript
        self.suggestedPatternIDs = suggestedPatternIDs
        self.selectedPatternID = selectedPatternID
        self.keyPoints = keyPoints
        self.grammarSuggestions = grammarSuggestions
        self.recordingDuration = recordingDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The suggested patterns, resolved against the catalog in ranked order.
    ///
    /// Ids no longer in the catalog are dropped rather than surfaced as placeholders — a
    /// retired pattern should simply stop appearing.
    public var suggestedPatterns: [SpeechPattern] {
        SpeechPatternCatalog.patterns(ids: suggestedPatternIDs)
    }

    /// The selected pattern, resolved against the catalog.
    public var selectedPattern: SpeechPattern? {
        selectedPatternID.flatMap { SpeechPatternCatalog.pattern(id: $0) }
    }

    /// The lightweight projection shown in the Home list.
    public var summary: ScriptSummary {
        ScriptSummary(
            id: id,
            title: title,
            purpose: purpose,
            createdAt: createdAt,
            recordingDuration: recordingDuration
        )
    }
}
