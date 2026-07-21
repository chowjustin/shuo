//
//  FetchScriptUseCaseTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Testing
import ShuoTestSupport
@testable import ShuoCore

@Suite("Fetch script use case")
struct FetchScriptUseCaseTests {

    private func storedScript() -> Script {
        Script(
            title: "Why remote work stuck",
            purpose: .inform,
            transcript: Transcript(original: "Original text.", refined: "Refined text."),
            suggestedPatternIDs: ["inform.topical"],
            selectedPatternID: "inform.topical",
            keyPoints: [
                KeyPoint(componentID: "topicOverview", componentName: "Topic Overview",
                         text: "Overview.", orderIndex: 0),
            ],
            recordingDuration: 90,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("The hydrated draft carries existingScriptID so saving updates in place")
    func hydratedDraftMarksItsOrigin() async throws {
        // Forgetting this field is what would silently duplicate the script on next save,
        // which is exactly why the conversion lives here rather than at each call site.
        let script = storedScript()
        let repository = FakeScriptRepository(scripts: [script])
        let fetch = FetchScriptUseCase(repository: repository)

        let draft = try await fetch(id: script.id)

        #expect(draft?.existingScriptID == script.id)
        #expect(draft?.isReopenedScript == true)
    }

    @Test("Every field carries across into the draft")
    func hydratesEveryField() async throws {
        let script = storedScript()
        let repository = FakeScriptRepository(scripts: [script])
        let fetch = FetchScriptUseCase(repository: repository)

        let draft = try #require(try await fetch(id: script.id))

        #expect(draft.title == script.title)
        #expect(draft.purpose == script.purpose)
        #expect(draft.transcript == script.transcript)
        #expect(draft.suggestedPatternIDs == script.suggestedPatternIDs)
        #expect(draft.selectedPatternID == script.selectedPatternID)
        #expect(draft.keyPoints == script.keyPoints)
        #expect(draft.recordingDuration == script.recordingDuration)
    }

    @Test("The draft carries no speech source")
    func doesNotHydrateSource() async throws {
        // A file URL or audio recording is meaningless once saved, and keeping one would
        // imply the source media is still available when it may not be.
        let script = storedScript()
        let repository = FakeScriptRepository(scripts: [script])
        let fetch = FetchScriptUseCase(repository: repository)

        let draft = try await fetch(id: script.id)

        #expect(draft?.source == nil)
    }

    @Test("Fetching a script that does not exist returns nil")
    func missingScriptReturnsNil() async throws {
        let repository = FakeScriptRepository()
        let fetch = FetchScriptUseCase(repository: repository)

        let draft = try await fetch(id: UUID())

        #expect(draft == nil)
    }

    @Test("Repository errors propagate unchanged")
    func propagatesRepositoryErrors() async {
        let repository = FakeScriptRepository(throwing: .persistenceFailed)
        let fetch = FetchScriptUseCase(repository: repository)

        await #expect(throws: ShuoError.persistenceFailed) {
            try await fetch(id: UUID())
        }
    }
}
