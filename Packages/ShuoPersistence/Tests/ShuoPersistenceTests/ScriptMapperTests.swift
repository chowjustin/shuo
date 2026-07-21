//
//  ScriptMapperTests.swift
//  ShuoPersistenceTests
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Testing
import ShuoCore
@testable import ShuoPersistence

@Suite("Script mapper")
struct ScriptMapperTests {

    /// A script with every optional populated, so a dropped field shows up as a failure
    /// rather than as a nil that happened to match.
    static func fullyPopulatedScript() -> Script {
        Script(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            title: "Why remote work stuck",
            purpose: .inform,
            transcript: Transcript(original: "Original text.", refined: "Refined text."),
            suggestedPatternIDs: ["inform.topical", "inform.causeEffect"],
            selectedPatternID: "inform.topical",
            keyPoints: [
                KeyPoint(componentID: "topicOverview", componentName: "Topic Overview",
                         text: "Remote work since 2020.", orderIndex: 0),
                KeyPoint(componentID: "category1", componentName: "Category 1",
                         text: KeyPoint.absentText, orderIndex: 1,
                         suggestion: "First major aspect"),
            ],
            grammarSuggestions: [
                GrammarSuggestion(originalPhrase: "kind of",
                                  suggestedPhrase: "somewhat",
                                  explanation: "Tighter phrasing."),
            ],
            recordingDuration: 184.5,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_003_600)
        )
    }

    @Test("A script survives a round trip through the entity unchanged")
    func roundTripPreservesEveryField() throws {
        let original = Self.fullyPopulatedScript()

        let entity = ScriptMapper.toEntity(original)
        let restored = try ScriptMapper.toDomain(entity)

        #expect(restored == original)
    }

    @Test("A script with every optional empty round-trips too")
    func roundTripWithEmptyOptionals() throws {
        let minimal = Script(
            title: "Untitled",
            purpose: .persuade,
            transcript: Transcript(original: "Just the original."),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let restored = try ScriptMapper.toDomain(ScriptMapper.toEntity(minimal))

        #expect(restored == minimal)
        #expect(restored.transcript.refined == nil)
        #expect(restored.selectedPatternID == nil)
        #expect(restored.recordingDuration == nil)
        #expect(restored.keyPoints.isEmpty)
    }

    @Test("Updating an entity in place overwrites content but keeps its identity")
    func applyUpdatesInPlace() throws {
        let entity = ScriptMapper.toEntity(Self.fullyPopulatedScript())
        let entityID = entity.id

        var updated = Self.fullyPopulatedScript()
        updated.title = "A better title"
        updated.transcript.refined = "Newly refined."
        updated.selectedPatternID = "inform.causeEffect"
        updated.updatedAt = Date(timeIntervalSince1970: 1_700_007_200)

        ScriptMapper.apply(updated, to: entity)
        let restored = try ScriptMapper.toDomain(entity)

        #expect(entity.id == entityID, "updating must not change the stored row's identity")
        #expect(restored == updated)
    }

    @Test("An unrecognized purpose is a persistence failure, not a silent default")
    func unknownPurposeThrows() {
        // A row written by a build this one doesn't understand. Substituting a default
        // would show the user someone else's speech type without telling them.
        let entity = ScriptMapper.toEntity(Self.fullyPopulatedScript())
        entity.purposeRawValue = "entertain"

        #expect(throws: ShuoError.persistenceFailed) {
            try ScriptMapper.toDomain(entity)
        }
    }

    @Test("The summary projection carries the Home list's fields")
    func summaryProjection() throws {
        let entity = ScriptMapper.toEntity(Self.fullyPopulatedScript())

        let summary = try ScriptMapper.toSummary(entity)

        #expect(summary.id == entity.id)
        #expect(summary.title == "Why remote work stuck")
        #expect(summary.purpose == .inform)
        #expect(summary.recordingDuration == 184.5)
        #expect(summary.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("An unrecognized purpose also fails when projecting a summary")
    func summaryRejectsUnknownPurpose() {
        let entity = ScriptMapper.toEntity(Self.fullyPopulatedScript())
        entity.purposeRawValue = ""

        #expect(throws: ShuoError.persistenceFailed) {
            try ScriptMapper.toSummary(entity)
        }
    }
}
