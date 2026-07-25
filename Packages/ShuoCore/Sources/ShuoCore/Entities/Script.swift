//
//  Script.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// A saved speech: everything the user produced and everything the model generated for it.
public struct Script: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public var title: String
    public let purpose: SpeechPurpose
    /// The original transcript, plus the refined version if the user regenerated one.
    public var transcript: Transcript
    /// Catalog ids of the patterns suggested for this script, best first.
    public var suggestedPatternIDs: [SpeechPattern.ID]
    /// The pattern the key points and refined transcript belong to.
    public var selectedPatternID: SpeechPattern.ID?
    /// Key points for `selectedPatternID`, one per component of that pattern.
    public var keyPoints: [KeyPoint]
    /// Key points for **every** suggested pattern that has been generated, keyed by pattern id.
    public var keyPointsByPattern: [SpeechPattern.ID: [KeyPoint]]
    /// Refined transcripts for **every** pattern the user generated one for, keyed by pattern id.
    public var refinedByPattern: [SpeechPattern.ID: String]
    /// Reserved for the deferred grammar feature (CLAUDE.md §8, §11).
    public var grammarSuggestions: [GrammarSuggestion]
    /// Duration of the source recording, when the script came from audio or video.
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
        keyPointsByPattern: [SpeechPattern.ID: [KeyPoint]] = [:],
        refinedByPattern: [SpeechPattern.ID: String] = [:],
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
        self.keyPointsByPattern = keyPointsByPattern
        self.refinedByPattern = refinedByPattern
        self.grammarSuggestions = grammarSuggestions
        self.recordingDuration = recordingDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The suggested patterns, resolved against the catalog in ranked order.
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
