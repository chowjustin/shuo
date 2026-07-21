//
//  ScriptDraft.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `ScriptDraft` — mutable in-flight state for the entire create/reopen
// flow, owned by `CreateScriptCoordinator`. `existingScriptID` is nil for a brand-new
// draft and set when reopening a saved script; that's what tells `SaveScriptUseCase`
// whether to insert or update. See ARCHITECTURE.md §6.

import Foundation

/// The working state of a speech as the user moves through create → analyze → save.
///
/// Distinct from `Script` because their lifecycles differ: a draft is mutable, may be
/// abandoned, and holds things that are never persisted (the `SpeechSource` the transcript
/// came from). A `Script` is the settled record. Keeping them separate is also what makes
/// "reopening a saved script" and "creating a new one" the same screen driven by the same
/// type, differing only in whether `existingScriptID` is set (CLAUDE.md §12).
public struct ScriptDraft: Sendable, Identifiable, Equatable {
    /// Identity of this editing session, not of the saved script.
    public let id: UUID
    /// The script being edited, when reopening. Nil for a new draft — which is precisely
    /// what `SaveScriptUseCase` reads to decide insert versus update.
    public var existingScriptID: UUID?
    public var title: String
    public let purpose: SpeechPurpose
    /// Where the transcript came from. Never persisted — a file URL or an audio recording
    /// is meaningless once the script is saved, and retaining it would imply the source
    /// media is still available when it may not be.
    public var source: SpeechSource?
    public var transcript: Transcript
    /// Catalog ids of the suggested patterns, best first.
    public var suggestedPatternIDs: [SpeechPattern.ID]
    /// The pattern currently selected, whose key points are on screen.
    public var selectedPatternID: SpeechPattern.ID?
    /// Key points for `selectedPatternID`.
    public var keyPoints: [KeyPoint]
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

    /// Hydrates a draft for reopening `script`, with `existingScriptID` set so saving
    /// updates rather than duplicates.
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
            recordingDuration: script.recordingDuration
        )
    }
}
