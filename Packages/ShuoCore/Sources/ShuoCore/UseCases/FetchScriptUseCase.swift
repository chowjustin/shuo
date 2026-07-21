//
//  FetchScriptUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: fetches a full `Script` by id for reopening, hydrating a `ScriptDraft` with
// `existingScriptID` set. See ARCHITECTURE.md §3.3, §6.

import Foundation

/// Loads a saved script and hands back a draft ready to reopen it.
///
/// Returning a `ScriptDraft` rather than a `Script` is the point: reopening and creating
/// share one screen and one type, differing only in whether `existingScriptID` is set
/// (CLAUDE.md §12). Doing the conversion here means no caller has to remember to set that
/// field — forgetting it would silently duplicate the script on the next save.
public struct FetchScriptUseCase: Sendable {

    private let repository: any ScriptRepository

    public init(repository: any ScriptRepository) {
        self.repository = repository
    }

    /// - Returns: A draft hydrated from the stored script, or nil if it no longer exists.
    /// - Throws: `ShuoError.persistenceFailed`.
    public func callAsFunction(id: UUID) async throws -> ScriptDraft? {
        guard let script = try await repository.fetch(id: id) else { return nil }
        return ScriptDraft(reopening: script)
    }
}
