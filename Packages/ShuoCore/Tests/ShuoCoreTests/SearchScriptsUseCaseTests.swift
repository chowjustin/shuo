//
//  SearchScriptsUseCaseTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 13/07/26.
//

// PLACEHOLDER — this file contains no tests. `SearchScriptsUseCase` is itself an empty
// stub, as is `FetchScriptSummariesUseCase`, which has no test file at all.

import Foundation
import Testing
import ShuoTestSupport
@testable import ShuoCore

@Suite("Search scripts use case")
struct SearchScriptsUseCaseTests {

    private func script(title: String, createdAt: Date) -> Script {
        Script(
            title: title,
            purpose: .inform,
            transcript: Transcript(original: "placeholder"),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private var scripts: [Script] {
        [
            script(title: "Graduation Speech", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            script(title: "Wedding Toast", createdAt: Date(timeIntervalSince1970: 1_700_003_600)),
            script(title: "Board Meeting Update", createdAt: Date(timeIntervalSince1970: 1_700_007_200)),
        ]
    }

    @Test("matches are case-insensitive")
    func matchesAreCaseInsensitive() async throws {
        let search = SearchScriptsUseCase(repository: FakeScriptRepository(scripts: scripts))

        let result = try await search(query: "GRAD")

        #expect(result.map(\.title) == ["Graduation Speech"])
    }

    @Test("matches anywhere in the title, not just the start")
    func matchesMidTitle() async throws {
        let search = SearchScriptsUseCase(repository: FakeScriptRepository(scripts: scripts))

        let result = try await search(query: "meeting")

        #expect(result.map(\.title) == ["Board Meeting Update"])
    }

    @Test("a blank query returns everything, newest first")
    func blankQueryReturnsEverythingNewestFirst() async throws {
        let search = SearchScriptsUseCase(repository: FakeScriptRepository(scripts: scripts))

        let result = try await search(query: "")

        #expect(result.map(\.title) == ["Board Meeting Update", "Wedding Toast", "Graduation Speech"])
    }

    @Test("no match returns an empty array, not an error")
    func noMatchReturnsEmpty() async throws {
        let search = SearchScriptsUseCase(repository: FakeScriptRepository(scripts: scripts))

        let result = try await search(query: "nonexistent")

        #expect(result.isEmpty)
    }

    @Test("a repository failure propagates unchanged")
    func propagatesRepositoryErrors() async {
        let search = SearchScriptsUseCase(repository: FakeScriptRepository(throwing: .persistenceFailed))

        await #expect(throws: ShuoError.persistenceFailed) {
            try await search(query: "anything")
        }
    }
}
