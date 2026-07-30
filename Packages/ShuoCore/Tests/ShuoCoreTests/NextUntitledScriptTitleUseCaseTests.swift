//
//  NextUntitledScriptTitleUseCaseTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 30/07/26.
//

import Foundation
import ShuoCore
import ShuoTestSupport
import Testing

@Suite("Next untitled script title use case")
struct NextUntitledScriptTitleUseCaseTests {
    /// A fixed timestamp: nothing here depends on ordering, and a real `Date()` would make
    /// the fixture the only nondeterministic part of the test.
    private static let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func script(titled title: String) -> Script {
        Script(
            title: title,
            purpose: .inform,
            transcript: Transcript(original: "A short speech about something."),
            createdAt: Self.savedAt,
            updatedAt: Self.savedAt
        )
    }

    @Test("An empty library produces the first name")
    func emptyLibraryProducesFirstName() async throws {
        let useCase = NextUntitledScriptTitleUseCase(repository: FakeScriptRepository())

        #expect(try await useCase() == "Untitled Script 1")
    }

    @Test("Numbering continues past the untitled scripts already saved")
    func numbersPastSavedScripts() async throws {
        let repository = FakeScriptRepository(scripts: [
            script(titled: "Untitled Script 1"),
            script(titled: "Untitled Script 2"),
        ])
        let useCase = NextUntitledScriptTitleUseCase(repository: repository)

        #expect(try await useCase() == "Untitled Script 3")
    }

    @Test("Scripts the user named do not consume a number")
    func namedScriptsDoNotConsumeNumbers() async throws {
        let repository = FakeScriptRepository(scripts: [
            script(titled: "Why remote work stuck"),
            script(titled: "A talk about bees"),
        ])
        let useCase = NextUntitledScriptTitleUseCase(repository: repository)

        #expect(try await useCase() == "Untitled Script 1")
    }

    @Test("A user title that merely contains the stem does not affect numbering")
    func looseMatchesDoNotAffectNumbering() async throws {
        // The store's search is a case-insensitive substring match, so these come back
        // from the query; the strict parse is what keeps them out of the count.
        let repository = FakeScriptRepository(scripts: [
            script(titled: "Untitled Script ideas"),
            script(titled: "untitled script 40"),
            script(titled: "My Untitled Script 90"),
        ])
        let useCase = NextUntitledScriptTitleUseCase(repository: repository)

        #expect(try await useCase() == "Untitled Script 1")
    }

    @Test("A gap left behind is skipped rather than filled")
    func skipsGaps() async throws {
        let repository = FakeScriptRepository(scripts: [
            script(titled: "Untitled Script 1"),
            script(titled: "Untitled Script 4"),
        ])
        let useCase = NextUntitledScriptTitleUseCase(repository: repository)

        #expect(try await useCase() == "Untitled Script 5")
    }

    @Test("The store is queried by the unnumbered stem, not by a full title")
    func queriesByStem() async throws {
        let repository = FakeScriptRepository()
        let useCase = NextUntitledScriptTitleUseCase(repository: repository)

        _ = try await useCase()

        #expect(await repository.searchQueries == ["Untitled Script"])
    }

    @Test("A store that cannot be read surfaces the failure rather than guessing a number")
    func propagatesRepositoryFailure() async {
        let repository = FakeScriptRepository(throwing: .persistenceFailed)
        let useCase = NextUntitledScriptTitleUseCase(repository: repository)

        await #expect(throws: ShuoError.persistenceFailed) {
            _ = try await useCase()
        }
    }
}
