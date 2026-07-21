//
//  SwiftDataScriptRepositoryTests.swift
//  ShuoPersistenceTests
//
//  Created by Justin Chow on 13/07/26.
//

// Swift Testing suite for `SwiftDataScriptRepository` against a real in-memory
// `ModelContainer` (via `ModelContainerFactory`) — round-trips save/fetch/search
// (CLAUDE.md §7).

import Foundation
import Testing
import ShuoCore
import SwiftData
@testable import ShuoPersistence

@Suite("SwiftData script repository")
struct SwiftDataScriptRepositoryTests {

    /// A fresh in-memory store per test, built from the same factory the app uses so the
    /// schema under test can never drift from the shipped one (CLAUDE.md §7).
    private func makeRepository() throws -> SwiftDataScriptRepository {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        return SwiftDataScriptRepository(modelContainer: container)
    }

    private func script(
        id: UUID = UUID(),
        title: String = "A speech",
        purpose: SpeechPurpose = .inform,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Script {
        Script(
            id: id,
            title: title,
            purpose: purpose,
            transcript: Transcript(original: "Original text.", refined: "Refined text."),
            suggestedPatternIDs: ["inform.topical"],
            selectedPatternID: "inform.topical",
            keyPoints: [
                KeyPoint(componentID: "topicOverview", componentName: "Topic Overview",
                         text: "Overview content.", orderIndex: 0),
            ],
            recordingDuration: 120,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    // MARK: - Save and fetch

    @Test("A saved script round-trips with every field intact")
    func saveThenFetchRoundTrips() async throws {
        let repository = try makeRepository()
        let original = ScriptMapperTests.fullyPopulatedScript()

        try await repository.save(original)
        let fetched = try await repository.fetch(id: original.id)

        #expect(fetched == original)
    }

    @Test("Fetching an id that was never saved returns nil rather than throwing")
    func fetchMissingReturnsNil() async throws {
        // Reopening something that has been removed is an ordinary outcome, not a failure.
        let repository = try makeRepository()

        let fetched = try await repository.fetch(id: UUID())

        #expect(fetched == nil)
    }

    @Test("Saving the same id twice updates the script instead of duplicating it")
    func saveIsIdempotentByID() async throws {
        let repository = try makeRepository()
        let id = UUID()
        var original = script(id: id, title: "First title")

        try await repository.save(original)
        original.title = "Second title"
        original.transcript.refined = "Newly refined."
        try await repository.save(original)

        let summaries = try await repository.fetchSummaries()
        #expect(summaries.count == 1, "a retry or re-save must not create a duplicate row")
        #expect(summaries.first?.title == "Second title")

        let fetched = try await repository.fetch(id: id)
        #expect(fetched?.transcript.refined == "Newly refined.")
    }

    @Test("Key points survive storage as a Codable value array")
    func keyPointsRoundTrip() async throws {
        let repository = try makeRepository()
        var original = script()
        original.keyPoints = [
            KeyPoint(componentID: "topicOverview", componentName: "Topic Overview",
                     text: "Filled.", orderIndex: 0),
            KeyPoint(componentID: "category1", componentName: "Category 1",
                     text: KeyPoint.absentText, orderIndex: 1, suggestion: "First aspect"),
        ]

        try await repository.save(original)
        let fetched = try await repository.fetch(id: original.id)

        #expect(fetched?.keyPoints.count == 2)
        #expect(fetched?.keyPoints.last?.isAbsent == true)
        #expect(fetched?.keyPoints.last?.suggestion == "First aspect")
    }

    @Test("Stored pattern ids resolve back to catalog patterns")
    func patternIDsResolveAgainstTheCatalog() async throws {
        // The reason patterns are stored as ids: the catalog stays the single source of
        // truth for their wording, and old scripts pick up improvements automatically.
        let repository = try makeRepository()
        var original = script()
        original.suggestedPatternIDs = ["inform.topical", "inform.spatial"]
        original.selectedPatternID = "inform.spatial"

        try await repository.save(original)
        let fetched = try await repository.fetch(id: original.id)

        #expect(fetched?.suggestedPatterns.map(\.name) == ["Topical (Categorical)", "Spatial"])
        #expect(fetched?.selectedPattern?.id == "inform.spatial")
    }

    // MARK: - Summaries

    @Test("Summaries come back newest first")
    func summariesAreNewestFirst() async throws {
        let repository = try makeRepository()
        try await repository.save(
            script(title: "Oldest", createdAt: Date(timeIntervalSince1970: 1_000))
        )
        try await repository.save(
            script(title: "Newest", createdAt: Date(timeIntervalSince1970: 3_000))
        )
        try await repository.save(
            script(title: "Middle", createdAt: Date(timeIntervalSince1970: 2_000))
        )

        let summaries = try await repository.fetchSummaries()

        #expect(summaries.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    @Test("An empty store yields no summaries")
    func emptyStoreYieldsNoSummaries() async throws {
        let repository = try makeRepository()

        let summaries = try await repository.fetchSummaries()

        #expect(summaries.isEmpty)
    }

    // MARK: - Search

    @Test("Search matches titles case-insensitively")
    func searchIsCaseInsensitive() async throws {
        let repository = try makeRepository()
        try await repository.save(script(title: "Remote Work Benefits"))
        try await repository.save(script(title: "Climate policy"))

        let results = try await repository.search(query: "remote")

        #expect(results.map(\.title) == ["Remote Work Benefits"])
    }

    @Test("Search matches a substring anywhere in the title")
    func searchMatchesSubstring() async throws {
        let repository = try makeRepository()
        try await repository.save(script(title: "Why remote work stuck"))

        let results = try await repository.search(query: "work")

        #expect(results.count == 1)
    }

    @Test("A blank query returns everything rather than nothing")
    func blankQueryReturnsEverything() async throws {
        // So the search field's empty state needs no special case at the call site.
        let repository = try makeRepository()
        try await repository.save(script(title: "One", createdAt: Date(timeIntervalSince1970: 1)))
        try await repository.save(script(title: "Two", createdAt: Date(timeIntervalSince1970: 2)))

        #expect(try await repository.search(query: "").count == 2)
        #expect(try await repository.search(query: "   ").count == 2)
    }

    @Test("A query matching nothing returns an empty result, not an error")
    func noMatchesReturnsEmpty() async throws {
        let repository = try makeRepository()
        try await repository.save(script(title: "Remote work"))

        let results = try await repository.search(query: "astrophysics")

        #expect(results.isEmpty)
    }

    @Test("Search results are newest first")
    func searchResultsAreNewestFirst() async throws {
        let repository = try makeRepository()
        try await repository.save(
            script(title: "Work: part one", createdAt: Date(timeIntervalSince1970: 1_000))
        )
        try await repository.save(
            script(title: "Work: part two", createdAt: Date(timeIntervalSince1970: 2_000))
        )

        let results = try await repository.search(query: "work")

        #expect(results.map(\.title) == ["Work: part two", "Work: part one"])
    }
}
