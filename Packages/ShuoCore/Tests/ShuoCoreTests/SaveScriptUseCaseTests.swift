//
//  SaveScriptUseCaseTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Testing
import ShuoTestSupport
@testable import ShuoCore

@Suite("Save script use case")
struct SaveScriptUseCaseTests {

    private static let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let savedAt = Date(timeIntervalSince1970: 1_700_003_600)

    private func draft(existingScriptID: UUID? = nil) -> ScriptDraft {
        ScriptDraft(
            existingScriptID: existingScriptID,
            title: "Why remote work stuck",
            purpose: .inform,
            transcript: Transcript(original: "Original text.", refined: "Refined text."),
            suggestedPatternIDs: ["inform.topical", "inform.causeEffect"],
            selectedPatternID: "inform.topical",
            keyPoints: [
                KeyPoint(componentID: "topicOverview", componentName: "Topic Overview",
                         text: "Overview.", orderIndex: 0),
            ],
            recordingDuration: 90
        )
    }

    // MARK: - Insert

    @Test("A new draft is saved as a new script")
    func insertsNewDraft() async throws {
        let repository = FakeScriptRepository()
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let saved = try await save(draft())

        #expect(saved.title == "Why remote work stuck")
        #expect(saved.purpose == .inform)
        #expect(saved.transcript.original == "Original text.")
        #expect(saved.suggestedPatternIDs == ["inform.topical", "inform.causeEffect"])
        #expect(saved.selectedPatternID == "inform.topical")
        #expect(saved.keyPoints.count == 1)
        #expect(saved.recordingDuration == 90)

        let count = await repository.saveCount
        #expect(count == 1)
    }

    @Test("A new script is stamped created and updated at the same moment")
    func newScriptTimestamps() async throws {
        let repository = FakeScriptRepository()
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let saved = try await save(draft())

        #expect(saved.createdAt == Self.savedAt)
        #expect(saved.updatedAt == Self.savedAt)
    }

    @Test("Each new draft gets its own identifier")
    func newDraftsGetDistinctIDs() async throws {
        let repository = FakeScriptRepository()
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let first = try await save(draft())
        let second = try await save(draft())

        #expect(first.id != second.id)
        let scripts = await repository.scripts
        #expect(scripts.count == 2)
    }

    // MARK: - Update

    @Test("A reopened draft updates the script it came from")
    func updatesReopenedDraft() async throws {
        let existing = Script(
            title: "Old title",
            purpose: .inform,
            transcript: Transcript(original: "Original text."),
            createdAt: Self.createdAt,
            updatedAt: Self.createdAt
        )
        let repository = FakeScriptRepository(scripts: [existing])
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let saved = try await save(draft(existingScriptID: existing.id))

        #expect(saved.id == existing.id, "an update must land on the original record")
        #expect(saved.title == "Why remote work stuck")

        let scripts = await repository.scripts
        #expect(scripts.count == 1, "updating must not leave a duplicate behind")
    }

    @Test("An update preserves the original creation date and advances updatedAt")
    func updatePreservesCreatedAt() async throws {
        // A reopened script that re-dated itself on every save would scramble the Home
        // list's newest-first ordering.
        let existing = Script(
            title: "Old title",
            purpose: .inform,
            transcript: Transcript(original: "Original text."),
            createdAt: Self.createdAt,
            updatedAt: Self.createdAt
        )
        let repository = FakeScriptRepository(scripts: [existing])
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let saved = try await save(draft(existingScriptID: existing.id))

        #expect(saved.createdAt == Self.createdAt)
        #expect(saved.updatedAt == Self.savedAt)
    }

    @Test("An update carries forward stored grammar suggestions the draft never held")
    func updatePreservesGrammarSuggestions() async throws {
        // `ScriptDraft` has no grammar field — that feature is deferred (CLAUDE.md §11).
        // Saving must not wipe data the draft simply doesn't model.
        let suggestion = GrammarSuggestion(
            originalPhrase: "kind of",
            suggestedPhrase: "somewhat",
            explanation: "Tighter phrasing."
        )
        let existing = Script(
            title: "Old title",
            purpose: .inform,
            transcript: Transcript(original: "Original text."),
            grammarSuggestions: [suggestion],
            createdAt: Self.createdAt,
            updatedAt: Self.createdAt
        )
        let repository = FakeScriptRepository(scripts: [existing])
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let saved = try await save(draft(existingScriptID: existing.id))

        #expect(saved.grammarSuggestions == [suggestion])
    }

    @Test("Reopening a script that has since vanished inserts it rather than failing")
    func missingOriginalFallsBackToInsert() async throws {
        // The user's work is worth more than the broken link.
        let missingID = UUID()
        let repository = FakeScriptRepository()
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        let saved = try await save(draft(existingScriptID: missingID))

        #expect(saved.id == missingID)
        #expect(saved.createdAt == Self.savedAt)
        let scripts = await repository.scripts
        #expect(scripts.count == 1)
    }

    // MARK: - Failure

    @Test("Repository errors propagate unchanged")
    func propagatesRepositoryErrors() async {
        let repository = FakeScriptRepository(throwing: .persistenceFailed)
        let save = SaveScriptUseCase(repository: repository, now: { Self.savedAt })

        await #expect(throws: ShuoError.persistenceFailed) {
            try await save(draft())
        }
    }
}
