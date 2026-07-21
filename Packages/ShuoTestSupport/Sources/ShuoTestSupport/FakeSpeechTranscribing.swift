//
//  FakeSpeechTranscribing.swift
//  ShuoTestSupport
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore

/// Scripted `SpeechTranscribing` for tests.
///
/// An actor so `receivedInputs` can be recorded without data races — callers await it to
/// assert *what* was handed to the transcriber, which is the whole point when the thing
/// under test is routing logic that may legitimately skip transcription entirely.
public actor FakeSpeechTranscribing: SpeechTranscribing {
    public enum Outcome: Sendable {
        case success(String)
        case failure(ShuoError)
    }

    private let outcome: Outcome
    /// Delay before returning. Non-zero lets a test observe the in-flight state, or
    /// cancel before the result lands.
    private let delay: Duration
    /// Every input passed to `transcribe(_:)`, in call order. Empty when the caller
    /// short-circuited and never transcribed anything.
    public private(set) var receivedInputs: [TranscriptionInput] = []

    public var callCount: Int { receivedInputs.count }

    public init(returning transcript: String, after delay: Duration = .zero) {
        self.outcome = .success(transcript)
        self.delay = delay
    }

    public init(throwing error: ShuoError, after delay: Duration = .zero) {
        self.outcome = .failure(error)
        self.delay = delay
    }

    public func transcribe(_ input: TranscriptionInput) async throws -> String {
        receivedInputs.append(input)
        if delay > .zero {
            // Honors cancellation: a cancelled sleep throws, so a cancelled caller never
            // sees the scripted result.
            try await Task.sleep(for: delay)
        }
        switch outcome {
        case .success(let transcript): return transcript
        case .failure(let error): throw error
        }
    }
}
