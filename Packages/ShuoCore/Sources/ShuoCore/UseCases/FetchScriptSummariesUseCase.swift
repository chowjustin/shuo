//
//  FetchScriptSummariesUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: fetches the `[ScriptSummary]` list backing the Home screen.

import Foundation

/// Fetches every saved script as a lightweight summary, for the Home list before any
/// search query has been entered.
public struct FetchScriptSummariesUseCase: Sendable {
    private let repository: any ScriptRepository

    public init(repository: any ScriptRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> [ScriptSummary] {
        try await repository.fetchSummaries()
    }
}
