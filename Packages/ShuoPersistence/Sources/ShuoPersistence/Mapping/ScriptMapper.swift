//
//  ScriptMapper.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// Maps `ScriptEntity` <-> `Script` in both directions. Exists so domain entities can
// stay plain `Sendable` structs, sidestepping SwiftData's Swift 6 actor-isolation sharp
// edges. See ARCHITECTURE.md §4.3.

import Foundation
import ShuoCore

/// Translates between the stored `ScriptEntity` and the domain's `Script`.
///
/// This is the reason `@Model` classes never leave `ShuoPersistence`. A `ScriptEntity` is
/// a reference type bound to a `ModelContext`; handing one to a use case or view model
/// would drag SwiftData's isolation rules through the whole app and make the domain
/// untestable without a live container. A `Script` is an inert `Sendable` struct that
/// crosses any boundary freely.
enum ScriptMapper {

    /// Entity → domain.
    ///
    /// - Throws: `ShuoError.persistenceFailed` when `purposeRawValue` is not a known
    ///   `SpeechPurpose`. That means the row was written by a build this one doesn't
    ///   understand; failing loudly beats silently substituting a default purpose and
    ///   showing the user someone else's speech type.
    static func toDomain(_ entity: ScriptEntity) throws -> Script {
        guard let purpose = SpeechPurpose(rawValue: entity.purposeRawValue) else {
            throw ShuoError.persistenceFailed
        }
        return Script(
            id: entity.id,
            title: entity.title,
            purpose: purpose,
            transcript: Transcript(
                original: entity.originalTranscript,
                refined: entity.refinedTranscript
            ),
            suggestedPatternIDs: entity.suggestedPatternIDs,
            selectedPatternID: entity.selectedPatternID,
            keyPoints: entity.keyPoints,
            grammarSuggestions: entity.grammarSuggestions,
            recordingDuration: entity.recordingDuration,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    /// Domain → a brand-new entity, for insertion.
    static func toEntity(_ script: Script) -> ScriptEntity {
        ScriptEntity(
            id: script.id,
            title: script.title,
            purposeRawValue: script.purpose.rawValue,
            originalTranscript: script.transcript.original,
            refinedTranscript: script.transcript.refined,
            suggestedPatternIDs: script.suggestedPatternIDs,
            selectedPatternID: script.selectedPatternID,
            keyPoints: script.keyPoints,
            grammarSuggestions: script.grammarSuggestions,
            recordingDuration: script.recordingDuration,
            createdAt: script.createdAt,
            updatedAt: script.updatedAt
        )
    }

    /// Domain → an existing entity, updated in place.
    ///
    /// Separate from `toEntity` because updating a stored row must not touch its `id`, and
    /// because deleting-then-inserting would churn the unique index and lose the row's
    /// identity for anything holding a reference to it.
    static func apply(_ script: Script, to entity: ScriptEntity) {
        entity.title = script.title
        entity.purposeRawValue = script.purpose.rawValue
        entity.originalTranscript = script.transcript.original
        entity.refinedTranscript = script.transcript.refined
        entity.suggestedPatternIDs = script.suggestedPatternIDs
        entity.selectedPatternID = script.selectedPatternID
        entity.keyPoints = script.keyPoints
        entity.grammarSuggestions = script.grammarSuggestions
        entity.recordingDuration = script.recordingDuration
        entity.createdAt = script.createdAt
        entity.updatedAt = script.updatedAt
    }

    /// Entity → the Home list's lightweight projection, without materializing a full
    /// `Script`.
    static func toSummary(_ entity: ScriptEntity) throws -> ScriptSummary {
        guard let purpose = SpeechPurpose(rawValue: entity.purposeRawValue) else {
            throw ShuoError.persistenceFailed
        }
        return ScriptSummary(
            id: entity.id,
            title: entity.title,
            purpose: purpose,
            createdAt: entity.createdAt,
            recordingDuration: entity.recordingDuration
        )
    }
}
