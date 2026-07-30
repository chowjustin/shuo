//
//  ScriptMapper.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore

/// Translates between the stored `ScriptEntity` and the domain's `Script`.
enum ScriptMapper {
    /// Entity → domain.
    ///
    /// - Throws: `ShuoError.persistenceFailed` when `purposeRawValue` is not a known `SpeechPurpose`.
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
            keyPointsByPattern: entity.keyPointsByPattern,
            refinedByPattern: entity.refinedByPattern,
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
            keyPointsByPattern: script.keyPointsByPattern,
            refinedByPattern: script.refinedByPattern,
            grammarSuggestions: script.grammarSuggestions,
            recordingDuration: script.recordingDuration,
            createdAt: script.createdAt,
            updatedAt: script.updatedAt
        )
    }

    /// Domain → an existing entity, updated in place.
    static func apply(_ script: Script, to entity: ScriptEntity) {
        entity.title = script.title
        entity.purposeRawValue = script.purpose.rawValue
        entity.originalTranscript = script.transcript.original
        entity.refinedTranscript = script.transcript.refined
        entity.suggestedPatternIDs = script.suggestedPatternIDs
        entity.selectedPatternID = script.selectedPatternID
        entity.keyPoints = script.keyPoints
        entity.keyPointsByPattern = script.keyPointsByPattern
        entity.refinedByPattern = script.refinedByPattern
        entity.grammarSuggestions = script.grammarSuggestions
        entity.recordingDuration = script.recordingDuration
        entity.createdAt = script.createdAt
        entity.updatedAt = script.updatedAt
    }

    /// Entity → the Home list's lightweight projection, without materializing a full `Script`.
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
