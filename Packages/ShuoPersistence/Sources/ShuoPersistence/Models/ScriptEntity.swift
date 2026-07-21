//
//  ScriptEntity.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// SwiftData `@Model` class mirroring `Script`. Scalar fields as attributes;
// patterns/keyPoints/grammarSuggestions stored as Codable value arrays rather than
// separate relationship entities. See ARCHITECTURE.md §12.3. Stays inside
// ShuoPersistence — never crosses a package boundary (CLAUDE.md §6).

import Foundation
import ShuoCore
import SwiftData

/// The stored form of a `Script`.
///
/// Two shape decisions worth knowing:
///
/// - **Key points and grammar suggestions are Codable value arrays, not relationships.**
///   They are only ever read and written as a complete set alongside their script, never
///   queried or sorted independently, so relationship entities would add join cost and
///   cascade-delete rules for no benefit (ARCHITECTURE.md §12.3).
/// - **Patterns are stored as catalog ids only.** The catalog is fixed app data; copying
///   a pattern's name and components into every row would leave old scripts rendering
///   stale wording after the catalog is improved.
///
/// `purposeRawValue` stores the raw string rather than the enum so an unrecognized value
/// from a future or downgraded build fails at the mapper — where it can be reported as
/// `persistenceFailed` — instead of failing to decode the whole row.
@Model
final class ScriptEntity {
    #Index<ScriptEntity>([\.createdAt])

    /// Matches `Script.id`. Unique so `save` is idempotent by id: a retry after a failure
    /// updates the row rather than inserting a duplicate.
    @Attribute(.unique) var id: UUID
    var title: String
    var purposeRawValue: String
    /// `Transcript` is flattened into two columns rather than stored as one Codable blob,
    /// so a future title/full-text search can reach the text through a predicate.
    var originalTranscript: String
    var refinedTranscript: String?
    var suggestedPatternIDs: [String]
    var selectedPatternID: String?
    var keyPoints: [KeyPoint]
    var grammarSuggestions: [GrammarSuggestion]
    var recordingDuration: TimeInterval?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        purposeRawValue: String,
        originalTranscript: String,
        refinedTranscript: String?,
        suggestedPatternIDs: [String],
        selectedPatternID: String?,
        keyPoints: [KeyPoint],
        grammarSuggestions: [GrammarSuggestion],
        recordingDuration: TimeInterval?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.purposeRawValue = purposeRawValue
        self.originalTranscript = originalTranscript
        self.refinedTranscript = refinedTranscript
        self.suggestedPatternIDs = suggestedPatternIDs
        self.selectedPatternID = selectedPatternID
        self.keyPoints = keyPoints
        self.grammarSuggestions = grammarSuggestions
        self.recordingDuration = recordingDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
