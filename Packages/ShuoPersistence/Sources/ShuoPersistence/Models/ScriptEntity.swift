//
//  ScriptEntity.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore
import SwiftData

/// The stored form of a `Script`.
@Model
final class ScriptEntity {
    #Index<ScriptEntity>([\.createdAt])

    /// Matches `Script.id`. Unique so `save` is idempotent by id.
    @Attribute(.unique) var id: UUID
    var title: String
    var purposeRawValue: String
    /// `Transcript` is flattened into two columns rather than stored as one Codable blob.
    var originalTranscript: String
    var refinedTranscript: String?
    var suggestedPatternIDs: [String]
    var selectedPatternID: String?
    var keyPoints: [KeyPoint]
    var keyPointsByPattern: [String: [KeyPoint]] = [:]
    var refinedByPattern: [String: String] = [:]
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
        keyPointsByPattern: [String: [KeyPoint]] = [:],
        refinedByPattern: [String: String] = [:],
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
        self.keyPointsByPattern = keyPointsByPattern
        self.refinedByPattern = refinedByPattern
        self.grammarSuggestions = grammarSuggestions
        self.recordingDuration = recordingDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
