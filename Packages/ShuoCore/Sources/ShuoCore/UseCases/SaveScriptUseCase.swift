//
//  SaveScriptUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// Persists a draft, inserting a new script or updating the one it was reopened from.
public struct SaveScriptUseCase: Sendable {

    private let repository: any ScriptRepository
    private let now: @Sendable () -> Date

    public init(
        repository: any ScriptRepository,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.now = now
    }

    /// - Returns: The saved script, with its identifiers and timestamps settled.
    /// - Throws: `ShuoError.persistenceFailed`.
    @discardableResult
    public func callAsFunction(_ draft: ScriptDraft) async throws -> Script {
        let timestamp = now()

        let existing = try await existingScript(for: draft)

        let script = Script(
            id: draft.existingScriptID ?? UUID(),
            title: draft.title,
            purpose: draft.purpose,
            transcript: draft.transcript,
            suggestedPatternIDs: draft.suggestedPatternIDs,
            selectedPatternID: draft.selectedPatternID,
            keyPoints: draft.keyPoints,
            keyPointsByPattern: perPatternKeyPoints(from: draft),
            refinedByPattern: perPatternRefinements(from: draft),
            grammarSuggestions: existing?.grammarSuggestions ?? [],
            recordingDuration: draft.recordingDuration,
            createdAt: existing?.createdAt ?? timestamp,
            updatedAt: timestamp
        )

        try await repository.save(script)
        return script
    }

    /// The per-pattern key points to persist, with the selected pattern's slice folded in from the top-level `keyPoints`.
    private func perPatternKeyPoints(from draft: ScriptDraft) -> [SpeechPattern.ID: [KeyPoint]] {
        var map = draft.keyPointsByPattern
        if let selected = draft.selectedPatternID, !draft.keyPoints.isEmpty {
            map[selected] = draft.keyPoints
        }
        return map
    }

    /// The per-pattern refined transcripts to persist, with the selected pattern's slice folded in from `transcript.refined`.
    private func perPatternRefinements(from draft: ScriptDraft) -> [SpeechPattern.ID: String] {
        var map = draft.refinedByPattern
        if let selected = draft.selectedPatternID, let refined = draft.transcript.refined,
           !refined.isEmpty {
            map[selected] = refined
        }
        return map
    }

    /// The stored script this draft came from, when it was reopened.
    private func existingScript(for draft: ScriptDraft) async throws -> Script? {
        guard let existingScriptID = draft.existingScriptID else { return nil }
        return try await repository.fetch(id: existingScriptID)
    }
}
