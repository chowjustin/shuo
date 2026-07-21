//
//  SaveScriptUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: `ScriptDraft` -> persisted `Script`, insert or update depending on whether
// `existingScriptID` is set. Delegates to `ScriptRepository`.

import Foundation

/// Persists a draft, inserting a new script or updating the one it was reopened from.
///
/// The insert/update decision is read from `ScriptDraft.existingScriptID` rather than
/// passed as a flag by the caller, so the two paths cannot diverge: a reopened draft
/// carries its origin, and every save of it lands on the same record.
///
/// `now` is injected rather than read from the system clock so timestamp behavior —
/// `createdAt` preserved across updates, `updatedAt` advanced — is testable without
/// sleeping or tolerating drift.
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

        // Preserve the original creation date when updating; a reopened script that
        // re-dated itself on every save would scramble the Home list's ordering.
        let existing = try await existingScript(for: draft)

        let script = Script(
            id: draft.existingScriptID ?? UUID(),
            title: draft.title,
            purpose: draft.purpose,
            transcript: draft.transcript,
            suggestedPatternIDs: draft.suggestedPatternIDs,
            selectedPatternID: draft.selectedPatternID,
            keyPoints: draft.keyPoints,
            grammarSuggestions: existing?.grammarSuggestions ?? [],
            recordingDuration: draft.recordingDuration,
            createdAt: existing?.createdAt ?? timestamp,
            updatedAt: timestamp
        )

        try await repository.save(script)
        return script
    }

    /// The stored script this draft came from, when it was reopened. Nil for a new draft,
    /// and also nil when the original has since disappeared — in which case saving falls
    /// through to inserting it afresh rather than failing, since the user's work is worth
    /// more than the broken link.
    private func existingScript(for draft: ScriptDraft) async throws -> Script? {
        guard let existingScriptID = draft.existingScriptID else { return nil }
        return try await repository.fetch(id: existingScriptID)
    }
}
