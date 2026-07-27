//
//  AudioPlaying.swift
//  ShuoCore
//

import Foundation

/// Plays back a captured take so the user can hear it before committing to it.
///
/// Unlike `AudioCapturing`, one instance serves many items over its lifetime: the user
/// replays, retakes, replays again. `events` therefore never completes, and `stop()`
/// returns the instance to a reusable idle state rather than retiring it.
public protocol AudioPlaying: Sendable {
    /// Position updates and end-of-item notifications, in order. Single-consumer, and
    /// live for the lifetime of the instance.
    var events: AsyncStream<AudioPlaybackEvent> { get }

    /// Starts playing `url`, or resumes it if it is the item already paused.
    ///
    /// Switching to a different url always restarts from the beginning — a take the user
    /// re-recorded shares nothing with the one before it, including a playhead.
    /// - Throws: `ShuoError.playbackFailed` if the item cannot be opened or the audio
    ///   session cannot be configured for playback.
    func play(url: URL) async throws

    /// Suspends playback, retaining the playhead so the next `play(url:)` for the same
    /// item continues from here.
    func pause() async

    /// Ends playback and releases the item. Never throws — this is the teardown path.
    func stop() async
}
