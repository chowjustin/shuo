//
//  FakeAudioPlaying.swift
//  ShuoTestSupport
//

import Foundation
import ShuoCore

/// `AudioPlaying` that records what it was asked to play and emits scripted events, so the
/// replay controls can be tested without an audio session.
///
/// Use `emit(_:)` to push an event onto `events` from a test.
public actor FakeAudioPlaying: AudioPlaying {
    public nonisolated let events: AsyncStream<AudioPlaybackEvent>
    private let continuation: AsyncStream<AudioPlaybackEvent>.Continuation

    /// Every url `play(url:)` was called with, in order — enough to assert that a paused
    /// take replays its preview and a finished one replays its own file.
    public private(set) var playedURLs: [URL] = []
    public private(set) var pauseCount = 0
    public private(set) var stopCount = 0

    private let playError: ShuoError?

    public init(playError: ShuoError? = nil) {
        self.playError = playError

        let (events, continuation) = AsyncStream.makeStream(of: AudioPlaybackEvent.self)
        self.events = events
        self.continuation = continuation
    }

    /// Pushes an event onto `events`. Nonisolated so tests can call it without `await`.
    public nonisolated func emit(_ event: AudioPlaybackEvent) {
        continuation.yield(event)
    }

    // MARK: - AudioPlaying

    public func play(url: URL) async throws {
        playedURLs.append(url)
        if let playError {
            throw playError
        }
    }

    public func pause() async {
        pauseCount += 1
    }

    public func stop() async {
        stopCount += 1
    }
}
