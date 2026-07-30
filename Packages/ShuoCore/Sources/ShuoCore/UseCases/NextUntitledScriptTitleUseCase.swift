//
//  NextUntitledScriptTitleUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 30/07/26.
//

import Foundation

/// Produces the name for a script the user did not title, numbered past every generated
/// name already saved.
public struct NextUntitledScriptTitleUseCase: Sendable {
    private let repository: any ScriptRepository

    public init(repository: any ScriptRepository) {
        self.repository = repository
    }

    /// The next `Untitled Script N`.
    ///
    /// Reads through `search(query:)` rather than `fetchSummaries()` so the store does the
    /// filtering instead of every saved script being handed back to be discarded. The query
    /// is a case-insensitive substring match on the unnumbered stem, which is a *superset*
    /// of the generated names — `UntitledScriptTitle` then decides strictly which of them
    /// actually count, so the loose match cannot let a user's own title affect numbering.
    /// - Throws: `ShuoError.persistenceFailed`.
    public func callAsFunction() async throws -> String {
        let candidates = try await repository.search(query: UntitledScriptTitle.prefix)
        return UntitledScriptTitle.next(after: candidates.map(\.title))
    }
}
