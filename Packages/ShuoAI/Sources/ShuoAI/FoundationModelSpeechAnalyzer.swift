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
/// **Three sessions, one per task.** Each carries its own `instructions`, so the model is
/// never asked to hold "you are a classifier" and "you are a rewriter" in the same
/// context. It also means each can be prewarmed independently, and a long refinement
/// can't push a classification's instructions out of its window.
///
/// This is a humble object by design (CLAUDE.md §7): it translates, it does not decide.
/// Ranking, validation, normalization, and the "-" rule all live in `ShuoCore` where they
/// are cheap to test. What is left here is prompt assembly, one framework call, and error
/// translation.
public actor FoundationModelSpeechAnalyzer: SpeechAnalyzing {

    private let model: SystemLanguageModel
    private let chunker: ContextWindowChunker

    /// Sessions are created lazily and then reused. Building one is not free, and the
    /// common path runs several calls in a row as the user browses patterns.
    private var classificationSession: LanguageModelSession?
    private var keyPointsSession: LanguageModelSession?
    private var refinementSession: LanguageModelSession?

    public init(model: SystemLanguageModel = .default) {
        self.model = model
        self.chunker = ContextWindowChunker(contextSize: model.contextSize)
    }

    /// Warms the classification session, which is always the first call of a flow.
    ///
    /// Best-effort and non-blocking: call it when the user starts recording or typing, and
    /// the first real request lands on an already-loaded model.
    public func prewarm() {
        session(for: .classification).prewarm()
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

    private func session(for kind: SessionKind) -> LanguageModelSession {
        switch kind {
        case .classification:
            if let classificationSession { return classificationSession }
            let created = LanguageModelSession(
                model: model,
                instructions: PromptBuilder.classificationInstructions
            )
            classificationSession = created
            return created

        case .keyPoints:
            if let keyPointsSession { return keyPointsSession }
            let created = LanguageModelSession(
                model: model,
                instructions: PromptBuilder.keyPointsInstructions
            )
            keyPointsSession = created
            return created

        case .refinement:
            if let refinementSession { return refinementSession }
            let created = LanguageModelSession(
                model: model,
                instructions: PromptBuilder.refinementInstructions
            )
            refinementSession = created
            return created
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
