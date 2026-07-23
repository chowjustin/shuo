//
//  SearchScriptsUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: title search over already-fetched `[ScriptSummary]` — naive in-memory
// filtering, no `#Predicate`-driven fetch, per the expected dataset size. See
// ARCHITECTURE.md §3.3, §2.4.

import Foundation

/// Searches saved scripts by title. A thin wrapper around
/// `ScriptRepository.search(query:)` — the repository owns the actual matching
/// semantics (case-insensitive, blank-returns-everything) so `FakeScriptRepository`
/// and the real SwiftData implementation are held to the same contract.
public struct SearchScriptsUseCase: Sendable {
    private let repository: any ScriptRepository

    public init(repository: any ScriptRepository) {
        self.repository = repository
    }

    public func callAsFunction(query: String) async throws -> [ScriptSummary] {
        try await repository.search(query: query)
    }
}

