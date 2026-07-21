//
//  FoundationModelSpeechAnalyzer.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Conforms to `SpeechAnalyzing` (ShuoCore). Owns the `LanguageModelSession`s and
// prewarm(). Prompt/instruction text is centralized in `PromptBuilder`, not inline here
// (CLAUDE.md §8). Gets minimal, mostly manual/integration test coverage — see
// ARCHITECTURE.md §8.

import Foundation
import FoundationModels
import ShuoCore

/// `SpeechAnalyzing` backed by Apple's on-device model.
///
/// An `actor` because `LanguageModelSession` is not `Sendable` and cannot serve
/// overlapping requests — a second call while one is in flight throws
/// `concurrentRequests`. Actor isolation serializes them instead, which also matches the
/// hardware: the neural engine runs one generation at a time regardless.
///
/// **One session per request, never reused.** Each kind of call carries its own
/// `instructions`, so the model is never asked to hold "you are a classifier" and "you are
/// a rewriter" in the same context.
///
/// Reuse is what makes this wrong: `LanguageModelSession` replays its accumulated
/// transcript on every `respond`, so a cached session eventually overflows the window on a
/// transcript that fit fine before. `ContextWindowChunker` cannot see that history, so its
/// budget check passes while the real request fails.
///
/// This is a humble object by design (CLAUDE.md §7): it translates, it does not decide.
/// Ranking, validation, normalization, and the "-" rule all live in `ShuoCore` where they
/// are cheap to test. What is left here is prompt assembly, one framework call, and error
/// translation.
public actor FoundationModelSpeechAnalyzer: SpeechAnalyzing {

    private let model: SystemLanguageModel
    private let chunker: ContextWindowChunker

    /// Consumed by the next classification call, so the warm-up isn't thrown away.
    private var prewarmedSession: LanguageModelSession?

    public init(model: SystemLanguageModel = .default) {
        self.model = model
        self.chunker = ContextWindowChunker(contextSize: model.contextSize)
    }

    /// Warms the classification session, which is always the first call of a flow.
    ///
    /// Best-effort and non-blocking: call it when the user starts recording or typing, and
    /// the first real request lands on an already-loaded model.
    public func prewarm() {
        let session = makeSession(for: .classification)
        session.prewarm()
        prewarmedSession = session
    }

    // MARK: - SpeechAnalyzing

    public func classify(
        transcript: String,
        purpose: SpeechPurpose,
        candidates: [SpeechPattern]
    ) async throws -> PatternClassification {
        guard !candidates.isEmpty else { throw ShuoError.aiGenerationFailed }

        let schema = try ClassificationSchema.make(candidates: candidates)
        // Classification reads the shape of the speech, which survives losing the middle
        // of an over-long transcript — so condense rather than chunk, and keep this to one
        // model call.
        let prompt = PromptBuilder.classificationPrompt(
            transcript: chunker.condensed(transcript),
            purpose: purpose,
            candidates: candidates
        )

        let content = try await respond(
            to: prompt,
            schema: schema,
            using: .classification
        )
        return try GeneratedContentMapper.classification(from: content)
    }

    public func generateKeyPoints(
        transcript: String,
        pattern: SpeechPattern
    ) async throws -> [KeyPoint] {
        let schema = try KeyPointsSchema.make(pattern: pattern)
        // Extraction needs the whole transcript — content for a late component lives in
        // late text — so chunk and merge instead of condensing.
        let chunks = chunker.chunks(transcript)

        var extracted: [KeyPoint] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let content = try await respond(
                to: PromptBuilder.keyPointsPrompt(transcript: chunk, pattern: pattern),
                schema: schema,
                using: .keyPoints
            )
            extracted.append(contentsOf: GeneratedContentMapper.keyPoints(
                from: content,
                pattern: pattern
            ))
        }

        // Deliberately unnormalized and possibly duplicated across chunks.
        // `KeyPointNormalizer` resolves that in the domain layer, keeping first
        // occurrences — which for a transcript read in order is the earliest mention.
        return extracted
    }

    public func refineTranscript(
        _ transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) async throws -> String {
        // Free prose, so no schema: constraining a rewrite to a structured shape would
        // only get in the way, and the key points already carry the structure.
        let prompt = PromptBuilder.refinementPrompt(
            transcript: chunker.condensed(transcript),
            pattern: pattern,
            keyPoints: keyPoints
        )

        do {
            let response = try await session(for: .refinement).respond(to: prompt)
            return response.content
        } catch {
            throw Self.domainError(from: error)
        }
    }

    public func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion] {
        // Defined by the protocol, deliberately unwired in v1 (CLAUDE.md §8, §11).
        // Returning empty rather than throwing keeps an accidental call harmless.
        []
    }

    // MARK: - Sessions

    private enum SessionKind {
        case classification, keyPoints, refinement
    }

    /// A session for exactly one request, with an empty transcript either way.
    private func session(for kind: SessionKind) -> LanguageModelSession {
        if case .classification = kind, let prewarmedSession {
            self.prewarmedSession = nil
            return prewarmedSession
        }
        return makeSession(for: kind)
    }

    private func makeSession(for kind: SessionKind) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: instructions(for: kind))
    }

    private func instructions(for kind: SessionKind) -> String {
        switch kind {
        case .classification: PromptBuilder.classificationInstructions
        case .keyPoints: PromptBuilder.keyPointsInstructions
        case .refinement: PromptBuilder.refinementInstructions
        }
    }

    /// One structured request, with framework errors translated at this boundary.
    private func respond(
        to prompt: String,
        schema: GenerationSchema,
        using kind: SessionKind
    ) async throws -> GeneratedContent {
        do {
            let response = try await session(for: kind).respond(to: prompt, schema: schema)
            return response.content
        } catch {
            throw Self.domainError(from: error)
        }
    }

    // MARK: - Error translation

    /// Maps a FoundationModels failure onto `ShuoError`, so nothing above this package
    /// catches an Apple framework error type (CLAUDE.md §5).
    ///
    /// Cancellation passes through untouched: a cancelled prefetch is not a failure, and
    /// converting it into a `ShuoError` would surface an error banner for work the user
    /// deliberately walked away from.
    static func domainError(from error: any Error) -> any Error {
        if error is CancellationError { return error }

        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return ShuoError.aiGenerationFailed
        }

        switch generationError {
        case .exceededContextWindowSize:
            return ShuoError.contextWindowExceeded
        case .assetsUnavailable:
            return ShuoError.aiUnavailable
        case .rateLimited, .concurrentRequests:
            // Transient and worth retrying, which is what `aiGenerationFailed` signals.
            return ShuoError.aiGenerationFailed
        case .guardrailViolation, .refusal:
            // The model declined the content. Not a crash and not retryable as-is, but the
            // user's recourse is the same as any generation failure: change the input.
            return ShuoError.aiGenerationFailed
        case .decodingFailure, .unsupportedGuide, .unsupportedLanguageOrLocale:
            return ShuoError.aiGenerationFailed
        @unknown default:
            return ShuoError.aiGenerationFailed
        }
    }
}
