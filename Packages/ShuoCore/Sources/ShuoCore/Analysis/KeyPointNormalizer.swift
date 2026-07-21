//
//  KeyPointNormalizer.swift
//  ShuoCore
//

// Turns whatever the model returned into exactly one `KeyPoint` per pattern component, in
// component order, with `KeyPoint.absentText` filling every slot the transcript did not
// cover. This is the type that makes the "-" rule a guarantee instead of a hope.

import Foundation

/// Forces a raw, model-produced key point list into the shape the rest of the app relies
/// on: one key point per component of the pattern, ordered by `SpeechPatternComponent`.
///
/// Structured generation constrains *shape*, not *semantics* — a small on-device model
/// will still skip components, repeat one, reorder them, or label a passage with a
/// component name that isn't in the pattern. Rather than scatter defensive checks through
/// the view model and the UI, every one of those failures is corrected once, here, by a
/// pure function that is cheap to test exhaustively.
///
/// The rules, in order of precedence:
/// - A component matched by exact `componentID` wins over one matched by display name.
/// - On duplicates, the first occurrence wins; later ones are discarded rather than
///   concatenated, since a repeated component usually means the model restated the same
///   passage rather than found a second one.
/// - Blank text, whitespace-only text, and text that is already `"-"` all count as absent.
/// - Components the model invented are dropped — they have no slot to live in.
/// - Components the model omitted become `KeyPoint.absent(for:)`, carrying ghost text
///   derived from the component's own `contains` hints.
public struct KeyPointNormalizer: Sendable {

    public init() {}

    /// Normalizes `rawKeyPoints` against `pattern`.
    ///
    /// The result always has `pattern.components.count` elements, in component order,
    /// regardless of what came in — including for an empty input, which yields an
    /// all-absent set. That is a legitimate outcome: it means the model found nothing in
    /// the transcript matching this structure, which is exactly what the user should see.
    public func normalize(
        _ rawKeyPoints: [KeyPoint],
        for pattern: SpeechPattern
    ) -> [KeyPoint] {
        let byID = firstOccurrences(of: rawKeyPoints, keyedBy: \.componentID)
        let byName = firstOccurrences(of: rawKeyPoints) {
            SpeechPattern.normalizeForMatching($0.componentName)
        }

        return pattern.components.map { component in
            let matched = byID[component.id]
                ?? byName[SpeechPattern.normalizeForMatching(component.name)]

            guard let matched, let text = Self.meaningfulText(matched.text) else {
                return KeyPoint.absent(for: component)
            }

            return KeyPoint(
                componentID: component.id,
                componentName: component.name,
                text: text,
                orderIndex: component.order,
                suggestion: nil
            )
        }
    }

    /// Trimmed text, or nil when the value carries no content — empty, whitespace-only,
    /// or the absent marker itself. Models routinely echo the "-" they were told to use
    /// for missing content, so treating it as absent rather than as literal text matters.
    static func meaningfulText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != KeyPoint.absentText else { return nil }
        return trimmed
    }

    /// Indexes by the given key, keeping the first occurrence of each. Entries whose key
    /// is empty are skipped so a blank component name can't shadow a real match.
    private func firstOccurrences(
        of keyPoints: [KeyPoint],
        keyedBy key: (KeyPoint) -> String
    ) -> [String: KeyPoint] {
        var result: [String: KeyPoint] = [:]
        for keyPoint in keyPoints {
            let identifier = key(keyPoint)
            guard !identifier.isEmpty, result[identifier] == nil else { continue }
            result[identifier] = keyPoint
        }
        return result
    }
}
