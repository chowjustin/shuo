//
//  FakeSpeechAnalyzing.swift
//  ShuoTestSupport
//
//  Created by Justin Chow on 13/07/26.
//

// Fake conforming to `SpeechAnalyzing` (ShuoCore), returning scripted classifications,
// key points, and refined transcripts for use-case and ViewModel tests.

import Foundation
import ShuoCore

/// Scripted `SpeechAnalyzing` for tests.
///
/// An actor, so call recording is race-free and an injected `delay` can hold a call
/// in-flight — which is how the analysis view model's cancellation and background-prefetch
/// behavior gets tested deterministically, without sleeping and hoping.
///
/// Key-point outcomes can be scripted per pattern id as well as globally. That matters for
/// the prefetch tests: they need pattern #1 to succeed while pattern #3 fails, and to
/// assert which patterns were actually asked for.
public actor FakeSpeechAnalyzing: SpeechAnalyzing {

    // MARK: - Scripted outcomes

    public enum ClassificationOutcome: Sendable {
        case success(PatternClassification)
        case failure(ShuoError)
    }

    public enum KeyPointsOutcome: Sendable {
        /// Return exactly these, unnormalized — the way a real model would.
        case success([KeyPoint])
        /// Fill every component of the requested pattern with placeholder text. The
        /// convenient default: it produces a well-formed, complete set without a test
        /// having to spell out five key points it doesn't care about.
        case fillAllComponents
        /// Fill only the components whose ids are listed, omitting the rest — the shape a
        /// real model produces for a transcript that covers a structure partially.
        case fillComponents(ids: Set<String>)
        case failure(ShuoError)
    }

    public enum RefineOutcome: Sendable {
        case success(String)
        /// Echo the transcript back with the pattern name prefixed, so a test can assert
        /// which pattern drove the refinement without hard-coding prose.
        case echoWithPatternName
        case failure(ShuoError)
    }

    /// One recorded `classify` call.
    public struct ClassifyCall: Sendable, Equatable {
        public let transcript: String
        public let purpose: SpeechPurpose
        public let candidateIDs: [SpeechPattern.ID]
    }

    // MARK: - Recorded calls

    public private(set) var classifyCalls: [ClassifyCall] = []
    /// Pattern ids passed to `generateKeyPoints`, in call order. Order is the assertion
    /// that matters for prefetch: the top pattern must be requested before the others.
    public private(set) var keyPointCalls: [SpeechPattern.ID] = []
    public private(set) var refineCalls: [SpeechPattern.ID] = []
    public private(set) var grammarCallCount = 0

    public var classifyCallCount: Int { classifyCalls.count }

    // MARK: - Configuration

    private var classification: ClassificationOutcome
    private var keyPoints: KeyPointsOutcome
    private var keyPointOverrides: [SpeechPattern.ID: KeyPointsOutcome] = [:]
    private var refined: RefineOutcome
    private var delay: Duration

    public init(
        classification: ClassificationOutcome = .success(.usable(rankedPatternIDs: [])),
        keyPoints: KeyPointsOutcome = .fillAllComponents,
        refined: RefineOutcome = .echoWithPatternName,
        delay: Duration = .zero
    ) {
        self.classification = classification
        self.keyPoints = keyPoints
        self.refined = refined
        self.delay = delay
    }

    public func setClassification(_ outcome: ClassificationOutcome) {
        classification = outcome
    }

    public func setKeyPoints(_ outcome: KeyPointsOutcome) {
        keyPoints = outcome
    }

    /// Scripts a specific pattern's key-point outcome, overriding the global one.
    public func setKeyPoints(_ outcome: KeyPointsOutcome, forPatternID id: SpeechPattern.ID) {
        keyPointOverrides[id] = outcome
    }

    public func setRefined(_ outcome: RefineOutcome) {
        refined = outcome
    }

    public func setDelay(_ newDelay: Duration) {
        delay = newDelay
    }

    // MARK: - SpeechAnalyzing

    public func classify(
        transcript: String,
        purpose: SpeechPurpose,
        candidates: [SpeechPattern]
    ) async throws -> PatternClassification {
        classifyCalls.append(
            ClassifyCall(
                transcript: transcript,
                purpose: purpose,
                candidateIDs: candidates.map(\.id)
            )
        )
        try await waitIfNeeded()
        switch classification {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    public func generateKeyPoints(
        transcript: String,
        pattern: SpeechPattern
    ) async throws -> [KeyPoint] {
        keyPointCalls.append(pattern.id)
        try await waitIfNeeded()
        switch keyPointOverrides[pattern.id] ?? keyPoints {
        case .success(let value):
            return value
        case .fillAllComponents:
            return Self.filled(pattern.components, in: pattern)
        case .fillComponents(let ids):
            return Self.filled(pattern.components.filter { ids.contains($0.id) }, in: pattern)
        case .failure(let error):
            throw error
        }
    }

    public func refineTranscript(
        _ transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) async throws -> String {
        refineCalls.append(pattern.id)
        try await waitIfNeeded()
        switch refined {
        case .success(let value): return value
        case .echoWithPatternName: return "[\(pattern.name)] \(transcript)"
        case .failure(let error): throw error
        }
    }

    public func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion] {
        grammarCallCount += 1
        try await waitIfNeeded()
        return []
    }

    // MARK: - Helpers

    private func waitIfNeeded() async throws {
        guard delay > .zero else { return }
        // A cancelled sleep throws, so a cancelled caller never observes the scripted
        // result — which is exactly the behavior cancellation tests need to assert.
        try await Task.sleep(for: delay)
    }

    private static func filled(
        _ components: [SpeechPatternComponent],
        in pattern: SpeechPattern
    ) -> [KeyPoint] {
        components.map { component in
            KeyPoint(
                componentID: component.id,
                componentName: component.name,
                text: "Content for \(component.name) of \(pattern.name).",
                orderIndex: component.order
            )
        }
    }
}
