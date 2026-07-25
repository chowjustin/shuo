//
//  ScriptDraft.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// The working state of a speech as the user moves through create → analyze → save.
public struct ScriptDraft: Sendable, Identifiable, Equatable {
    /// Identity of this editing session, not of the saved script.
    public let id: UUID
    /// The script being edited, when reopening.
    public var existingScriptID: UUID?
    public var title: String
    public let purpose: SpeechPurpose
    /// Where the transcript came from. Never persisted.
    public var source: SpeechSource?
    public var transcript: Transcript
    /// Catalog ids of the suggested patterns, best first.
    public var suggestedPatternIDs: [SpeechPattern.ID]
    /// The pattern currently selected, whose key points are on screen.
    public var selectedPatternID: SpeechPattern.ID?
    /// Key points for `selectedPatternID`.
    public var keyPoints: [KeyPoint]
    /// Key points for every suggested pattern generated so far, keyed by pattern id.
    public var keyPointsByPattern: [SpeechPattern.ID: [KeyPoint]]
    /// Refined transcripts already generated, keyed by pattern id.
    public var refinedByPattern: [SpeechPattern.ID: String]
    /// Duration of the source recording, when there was one.
    public var recordingDuration: TimeInterval?

    public init(
        id: UUID = UUID(),
        existingScriptID: UUID? = nil,
        title: String,
        purpose: SpeechPurpose,
        source: SpeechSource? = nil,
        transcript: Transcript,
        suggestedPatternIDs: [SpeechPattern.ID] = [],
        selectedPatternID: SpeechPattern.ID? = nil,
        keyPoints: [KeyPoint] = [],
        keyPointsByPattern: [SpeechPattern.ID: [KeyPoint]] = [:],
        refinedByPattern: [SpeechPattern.ID: String] = [:],
        recordingDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.existingScriptID = existingScriptID
        self.title = title
        self.purpose = purpose
        self.source = source
        self.transcript = transcript
        self.suggestedPatternIDs = suggestedPatternIDs
        self.selectedPatternID = selectedPatternID
        self.keyPoints = keyPoints
        self.keyPointsByPattern = keyPointsByPattern
        self.refinedByPattern = refinedByPattern
        self.recordingDuration = recordingDuration
    }

    /// True when saving this draft will update an existing script rather than insert one.
    public var isReopenedScript: Bool {
        existingScriptID != nil
    }

    /// The suggested patterns, resolved against the catalog in ranked order.
    public var suggestedPatterns: [SpeechPattern] {
        SpeechPatternCatalog.patterns(ids: suggestedPatternIDs)
    }

    /// The currently selected pattern, resolved against the catalog.
    public var selectedPattern: SpeechPattern? {
        selectedPatternID.flatMap { SpeechPatternCatalog.pattern(id: $0) }
    }

    /// Hydrates a draft for reopening `script`, with `existingScriptID` set so saving updates rather than duplicates.
    public init(reopening script: Script) {
        self.init(
            existingScriptID: script.id,
            title: script.title,
            purpose: script.purpose,
            source: nil,
            transcript: script.transcript,
            suggestedPatternIDs: script.suggestedPatternIDs,
            selectedPatternID: script.selectedPatternID,
            keyPoints: script.keyPoints,
            keyPointsByPattern: script.keyPointsByPattern,
            refinedByPattern: script.refinedByPattern,
            recordingDuration: script.recordingDuration
        )
    }
}
