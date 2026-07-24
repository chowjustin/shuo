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
                suggestion: component.contains.isEmpty ? nil : component.contains.joined(separator: ", ")
            )
        }
    }

    /// Trimmed text, or nil when the value carries no content — empty, whitespace-only,
    /// the absent marker itself, or prose describing the absence. Models routinely echo
    /// the "-" they were told to use for missing content, so treating it as absent rather
    /// than as literal text matters.
    static func meaningfulText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != KeyPoint.absentText else { return nil }
        guard !describesAbsence(trimmed) else { return nil }
        return trimmed
    }

    /// True when the text narrates a gap ("There is no call to action in the transcript.")
    /// instead of extracting content.
    ///
    /// The instructions tell the model to omit an uncovered component and the schema lets
    /// it, so it usually does. When it doesn't, it writes a sentence *about* the absence,
    /// which would otherwise render as though the speaker had said it — the exact failure
    /// the "-" rule exists to prevent.
    ///
    /// Deliberately conservative, because the two errors are not symmetric: a false
    /// positive silently deletes something the speaker really said, while a false negative
    /// only shows one odd sentence. So a match needs an unambiguously negative opening
    /// *and* a reference to the source material — "No easy answers." keeps its text.
    static func describesAbsence(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if standaloneAbsencePhrases.contains(normalized) { return true }
        guard absenceOpenings.contains(where: normalized.hasPrefix) else { return false }
        return sourceReferences.contains(where: normalized.contains)
    }

    /// Complete answers that mean "nothing here" on their own, with no source reference
    /// needed — no speaker says only these.
    private static let standaloneAbsencePhrases: Set<String> = [
        "none", "n/a", "na", "nothing", "unknown", "absent", "empty",
        "not applicable", "not mentioned", "not covered", "not specified",
        "not provided", "not present", "not addressed", "not discussed",
        "not stated", "not available", "not found", "not included",
        "no content", "no mention", "no data",
    ]

    /// Openings that cannot begin a genuine extraction. Paired with `sourceReferences` so
    /// a match requires the sentence to also be talking about the transcript.
    private static let absenceOpenings: [String] = [
        "there is no", "there are no", "there's no", "there isn't", "there aren't",
        "there was no", "there were no",
        "no ", "none ", "not ", "nothing ",
        "the transcript does not", "the transcript doesn't", "the transcript did not",
        "the transcript contains no", "the transcript has no", "the transcript provides no",
        "the speaker does not", "the speaker doesn't", "the speaker did not",
        "the speaker never", "the speech does not", "the draft does not",
        "unable to", "cannot find", "could not find",
    ]

    /// Words naming the source material. Their presence is what separates the model
    /// talking *about* the transcript from the speaker talking about their topic.
    private static let sourceReferences: [String] = [
        "transcript", "speech", "draft", "excerpt", "passage", "recording",
        "component", "section", "mention", "information", "material",
    ]

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
