//
//  FakeAudioCapturing.swift
//  ShuoTestSupport
//
//  Created by Justin Chow on 13/07/26.
//

// Fake conforming to `AudioCapturing` (ShuoCore); records start/pause/resume/finish
// call counts so ViewModel tests can assert the idle→recording→paused→recording→
// finished state machine without touching real hardware. See ARCHITECTURE.md §3.1.3.

import Foundation
import ShuoCore

/// `AudioCapturing` that records call counts and emits scripted events, so the recording
/// state machine can be tested without a microphone.
///
/// Use `emit(_:)` to push an event onto `events` from a test.
public actor FakeAudioCapturing: AudioCapturing {
    public nonisolated let events: AsyncStream<AudioCaptureEvent>
    private let continuation: AsyncStream<AudioCaptureEvent>.Continuation

    public private(set) var prepareCount = 0
    public private(set) var startCount = 0
    public private(set) var pauseCount = 0
    public private(set) var resumeCount = 0
    public private(set) var finishCount = 0
    public private(set) var discardCount = 0

    private let recording: AudioRecording
    private let startError: ShuoError?
    private let finishError: ShuoError?

    public init(
        recording: AudioRecording = FakeAudioCapturing.defaultRecording,
        startError: ShuoError? = nil,
        finishError: ShuoError? = nil
    ) {
        self.recording = recording
        self.startError = startError
        self.finishError = finishError

        let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
        self.events = events
        self.continuation = continuation
    }

    public static let defaultRecording = AudioRecording(
        fileURL: URL(filePath: "/tmp/recording.m4a"),
        duration: 6.4,
        waveformSamples: [0.2, 0.8, 0.5],
        liveTranscript: "Why we must join campus organizations."
    )

    /// Pushes an event onto `events`. Nonisolated so tests can call it without `await`.
    public nonisolated func emit(_ event: AudioCaptureEvent) {
        continuation.yield(event)
    }

    // MARK: - AudioCapturing

    public func prepare() async {
        prepareCount += 1
    }

    public func start() async throws {
        startCount += 1
        if let startError { throw startError }
    }

    public func pause() async throws {
        pauseCount += 1
    }

    public func resume() async throws {
        resumeCount += 1
    }

    public func finish() async throws -> AudioRecording {
        finishCount += 1
        if let finishError { throw finishError }
        continuation.finish()
        return recording
    }

    public func discard() async {
        discardCount += 1
        continuation.finish()
    }
}
