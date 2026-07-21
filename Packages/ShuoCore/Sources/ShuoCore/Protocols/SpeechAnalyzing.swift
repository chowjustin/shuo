//
//  SpeechAnalyzing.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `SpeechAnalyzing` — classify / generateKeyPoints / refineTranscript /
// analyzeGrammar. Implemented by `FoundationModelSpeechAnalyzer` in ShuoAI; use cases
// depend only on this protocol, never on `import FoundationModels` directly. See
// ARCHITECTURE.md §3.2.4. `analyzeGrammar` stays defined but unused in v1 (CLAUDE.md §8).

import Foundation

/// The on-device analysis capability the domain needs, stated without reference to any
/// Apple framework.
///
/// Three calls, matching the three steps of the analysis flow: decide what structure the
/// transcript fits, map its content onto that structure's components, then rewrite it to
/// follow the structure. Each is a separate model round trip because each has a different
/// cost and a different trigger — classification runs once, key-point extraction runs per
/// pattern the user looks at, and refinement runs only when the user asks for it.
///
/// Implementations are `Sendable` and may be actors; callers must assume every method can
/// suspend for seconds and must be cancellable.
public protocol SpeechAnalyzing: Sendable {

    /// Judges whether `transcript` is a usable speech script and, if so, ranks
    /// `candidates` by how well the transcript fits each.
    ///
    /// Both answers come from one call deliberately — see `PatternClassification`.
    /// `candidates` is always the catalog subset for the user's chosen purpose; passing
    /// it in rather than having the implementation reach for the catalog keeps the
    /// candidate set explicit and the implementation trivially testable.
    ///
    /// The returned ids are *unvalidated* — an implementation may return an id that is
    /// not in `candidates`. `ClassifyTranscriptUseCase` is responsible for rejecting
    /// those, so a hallucinated identifier can never reach the UI.
    ///
    /// - Throws: `ShuoError.aiUnavailable` when the model cannot run,
    ///   `ShuoError.contextWindowExceeded` when the transcript cannot be chunked to fit.
    func classify(
        transcript: String,
        purpose: SpeechPurpose,
        candidates: [SpeechPattern]
    ) async throws -> PatternClassification

    /// Extracts the transcript's content into `pattern`'s components.
    ///
    /// The result is *unnormalized*: components may be missing, duplicated, or unknown.
    /// `GenerateKeyPointsUseCase` runs it through `KeyPointNormalizer` to establish the
    /// one-per-component invariant. Implementations must not invent content for a
    /// component the transcript does not cover — leaving it out is correct, and the
    /// normalizer turns that into `KeyPoint.absentText`.
    func generateKeyPoints(
        transcript: String,
        pattern: SpeechPattern
    ) async throws -> [KeyPoint]

    /// Rewrites `transcript` so it follows `pattern`, using `keyPoints` as the outline.
    ///
    /// Key points are passed in rather than re-derived so the rewrite is anchored to
    /// exactly what the user has already been shown — otherwise the refined text can
    /// silently disagree with the key points displayed above it. Absent key points are
    /// included and must be left unexpanded: refinement restructures what the speaker
    /// said, it does not write new material for them.
    func refineTranscript(
        _ transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) async throws -> String

    /// Grammar and vocabulary suggestions. Defined for completeness; deliberately unwired
    /// in v1 (CLAUDE.md §8, §11) — do not call this from a use case or view model without
    /// picking that work back up explicitly.
    func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion]
}
