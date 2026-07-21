//
//  SpeechPatternComponent.swift
//  ShuoCore
//

// Domain entity: one named slot within a `SpeechPattern` — "Topic Overview", "Point",
// "Challenge". Each component is exactly one key-point slot, which is what makes
// `KeyPointNormalizer` able to guarantee one `KeyPoint` per component in catalog order.

import Foundation

/// A single named slot in a speech structure pattern.
///
/// Components are the unit key points map onto: `SpeechPatternCatalog` defines them,
/// `PromptBuilder` renders `contains`/`aiGuideline` into the extraction prompt, and
/// `KeyPointNormalizer` guarantees exactly one `KeyPoint` per component, in `order`.
///
/// `contains` and `aiGuideline` exist purely as *guidance to the model* — they are never
/// separate output slots. Sub-bullets like "Main subject / Brief introduction / Scope"
/// collapse into the single parent component's key point rather than fanning out into
/// three, which keeps generation latency proportional to the pattern's real structure.
/// See `Docs/SPEECH_PATTERNS.md` §1.
public struct SpeechPatternComponent: Sendable, Identifiable, Equatable, Codable, Hashable {
    /// Stable slug, unique within its owning pattern — e.g. `topicOverview`, `category1`.
    /// Persisted on `KeyPoint.componentID`, so it must not change once shipped.
    public let id: String
    /// Display name, e.g. "Topic Overview". This is also the string the model is asked to
    /// echo back when labelling extracted content, so it doubles as the match key in
    /// `KeyPointNormalizer`.
    public let name: String
    /// What belongs in this component, as authored in `Docs/SPEECH_PATTERNS.md`. Rendered
    /// into the prompt as a bulleted hint list.
    public let contains: [String]
    /// Extra extraction instruction, where the source material specified one. Most
    /// components have none — the name plus `contains` carries enough signal.
    public let aiGuideline: String?
    /// Position within the pattern, zero-based. Determines key-point ordering.
    public let order: Int

    public init(
        id: String,
        name: String,
        contains: [String],
        aiGuideline: String? = nil,
        order: Int
    ) {
        self.id = id
        self.name = name
        self.contains = contains
        self.aiGuideline = aiGuideline
        self.order = order
    }
}
