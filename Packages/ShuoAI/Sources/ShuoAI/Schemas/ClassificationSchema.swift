//
//  ClassificationSchema.swift
//  ShuoAI
//

// The generation schema for the classification pass, built dynamically because the valid
// pattern identifiers depend on the user's chosen purpose. Property names are declared
// here and read by `GeneratedContentMapper`, so the schema and its decoding cannot drift.

import Foundation
import FoundationModels
import ShuoCore

/// Builds the `GenerationSchema` that constrains a classification response.
///
/// This is a `DynamicGenerationSchema` rather than a `@Generable` struct for a reason
/// worth recording: `@Guide(.anyOf(...))` needs its values at compile time, but the valid
/// pattern identifiers are the catalog subset for whichever purpose the user picked. A
/// dynamic schema lets the *exact* candidate ids be baked into the grammar for this one
/// request, so the model is structurally prevented from returning an id from another
/// purpose or inventing one.
///
/// `ClassifyTranscriptUseCase` still validates the returned ids. Constrained decoding is a
/// strong guarantee, not an absolute one, and the domain should not depend on a framework
/// detail holding perfectly.
enum ClassificationSchema {

    /// Property names, shared with `GeneratedContentMapper`. String literals duplicated
    /// across a schema and its decoder are a classic silent-failure source; naming them
    /// once removes the possibility.
    enum Key {
        static let isUsable = "isUsable"
        static let rejectionReason = "rejectionReason"
        static let rankedPatternIDs = "rankedPatternIDs"
    }

    /// - Parameter candidates: The catalog patterns for the user's purpose. Their ids
    ///   become the only values the model can emit.
    /// - Throws: `ShuoError.aiGenerationFailed` if the schema cannot be assembled, which
    ///   would mean a malformed catalog rather than a runtime condition.
    static func make(candidates: [SpeechPattern]) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(
            name: "SpeechClassification",
            description: "Whether the transcript is a usable speech, and its best-matching structure patterns.",
            properties: [
                DynamicGenerationSchema.Property(
                    name: Key.isUsable,
                    description: "True if the transcript is a speech, talk, or presentation draft.",
                    schema: DynamicGenerationSchema(type: Bool.self)
                ),
                DynamicGenerationSchema.Property(
                    name: Key.rejectionReason,
                    description: "Why the transcript is not a speech. Omit when isUsable is true.",
                    schema: DynamicGenerationSchema(
                        name: "RejectionReason",
                        anyOf: TranscriptRejectionReason.allCases.map(\.rawValue)
                    ),
                    isOptional: true
                ),
                DynamicGenerationSchema.Property(
                    name: Key.rankedPatternIDs,
                    description: "Best-matching pattern identifiers, best first. Empty when isUsable is false.",
                    schema: DynamicGenerationSchema(
                        arrayOf: DynamicGenerationSchema(
                            name: "PatternIdentifier",
                            anyOf: candidates.map(\.id)
                        ),
                        maximumElements: ClassifyTranscriptUseCase.suggestionCount
                    )
                ),
            ]
        )

        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            throw ShuoError.aiGenerationFailed
        }
    }
}
