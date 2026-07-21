//
//  GeneratedContentMapper.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Decodes the `GeneratedContent` returned for each schema in Schemas/ into `ShuoCore`
// domain entities. Keeps FoundationModels types out of the domain layer entirely —
// Feature packages and ViewModels only ever see `SpeechPattern`, `KeyPoint`, etc.
// See ARCHITECTURE.md §3.2.4.

import Foundation
import FoundationModels
import ShuoCore

/// Turns raw `GeneratedContent` into domain values.
///
/// Split from the schema builders only by direction — the two halves share the property
/// names declared in `ClassificationSchema.Key` and `KeyPointsSchema.Key`, so they cannot
/// drift apart.
///
/// The decoding is deliberately forgiving about *semantics* and strict about *shape*. A
/// missing optional or an unrecognized enum value becomes a sensible default rather than a
/// thrown error, because a hard failure here would turn a slightly-off response into a
/// dead end for the user. What the mapper never does is invent content: unrecognized
/// component labels are dropped, and `KeyPointNormalizer` turns the resulting gaps into
/// visible "-" slots.
enum GeneratedContentMapper {

    /// Decodes a classification response.
    ///
    /// - Throws: `ShuoError.aiGenerationFailed` when the response has no `isUsable` field
    ///   at all, which means the shape is wrong rather than the content unexpected.
    static func classification(from content: GeneratedContent) throws -> PatternClassification {
        guard let isUsable = try? content.value(Bool.self, forProperty: ClassificationSchema.Key.isUsable) else {
            throw ShuoError.aiGenerationFailed
        }

        guard isUsable else {
            let rawReason = try? content.value(
                String?.self,
                forProperty: ClassificationSchema.Key.rejectionReason
            )
            // An unusable verdict with an unreadable reason is still an unusable verdict;
            // `.notASpeech` is the broadest honest reading of one.
            let reason = rawReason
                .flatMap { $0 }
                .flatMap(TranscriptRejectionReason.init(rawValue:))
            return .rejected(reason ?? .notASpeech)
        }

        let ids = (try? content.value(
            [String].self,
            forProperty: ClassificationSchema.Key.rankedPatternIDs
        )) ?? []
        return .usable(rankedPatternIDs: ids)
    }

    /// Decodes a key-point extraction response against the pattern it was generated for.
    ///
    /// Returns *unnormalized* key points — components may be missing or duplicated. That
    /// is `KeyPointNormalizer`'s job, in the domain layer where it is cheap to test.
    ///
    /// Entries whose component label matches nothing in the pattern are dropped here
    /// rather than passed along, since a `KeyPoint` carrying an unknown `componentID`
    /// would be meaningless downstream.
    static func keyPoints(
        from content: GeneratedContent,
        pattern: SpeechPattern
    ) -> [KeyPoint] {
        guard let entries = try? content.value(
            [GeneratedContent].self,
            forProperty: KeyPointsSchema.Key.keyPoints
        ) else {
            // No readable entries means the transcript covered nothing this pattern asks
            // for. An all-absent set is the right answer, not an error.
            return []
        }

        return entries.compactMap { entry in
            guard
                let label = try? entry.value(String.self, forProperty: KeyPointsSchema.Key.component),
                let component = pattern.component(matchingName: label)
            else {
                return nil
            }
            let text = (try? entry.value(String.self, forProperty: KeyPointsSchema.Key.content)) ?? ""
            return KeyPoint(
                componentID: component.id,
                componentName: component.name,
                text: text,
                orderIndex: component.order
            )
        }
    }
}
