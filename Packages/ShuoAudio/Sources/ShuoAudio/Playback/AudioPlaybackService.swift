//
//  AudioPlaybackService.swift
//  ShuoAudio
//

import AVFoundation
import Foundation
import OSLog
import ShuoCore

/// `AudioPlaying` backed by `AVAudioPlayer`.
///
/// An `actor` because `AVAudioPlayer` is not `Sendable` and the recording screen drives it
/// from the main actor while a ticker task reads its playhead — exactly the case CLAUDE.md
/// §6 says to isolate rather than suppress.
///
/// Progress is polled on a timer instead of through `AVAudioPlayerDelegate`: the delegate
/// is a class-bound protocol that would need an `NSObject` shim outside the actor to
/// receive callbacks, and the screen needs a moving playhead anyway, so the ticker that
/// draws it can detect the end of the item for free.
public actor AudioPlaybackService: AudioPlaying {

    /// 10Hz — a playhead that advances visibly without redrawing SwiftUI for nothing.
    private static let tickInterval: Duration = .milliseconds(100)

    private static let log = Logger(subsystem: "com.seven.shuo", category: "AudioPlayback")

    public nonisolated let events: AsyncStream<AudioPlaybackEvent>
    private let continuation: AsyncStream<AudioPlaybackEvent>.Continuation

    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var tickTask: Task<Void, Never>?

    public init() {
        let (events, continuation) = AsyncStream.makeStream(of: AudioPlaybackEvent.self)
        self.events = events
        self.continuation = continuation
    }

    // MARK: - AudioPlaying

    public func play(url: URL) async throws {
        if loadedURL != url { unload() }

        if player == nil {
            do {
                try configureSession()
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                self.player = player
                self.loadedURL = url
            } catch {
                // The one place the real AVFoundation error exists before it is flattened
                // into a domain error. Filter Console by subsystem `com.seven.shuo`.
                Self.log.error("Playback could not start: \(error.localizedDescription, privacy: .public)")
                unload()
                throw ShuoError.playbackFailed
            }
        }

        guard let player, player.play() else {
            unload()
            throw ShuoError.playbackFailed
        }
        startTicking()
    }

    public func pause() async {
        // Cancelled before pausing, so the ticker can read "stopped playing" as the item
        // having reached its end rather than as the user pausing it.
        stopTicking()
        player?.pause()
    }

    public func stop() async {
        stopTicking()
        unload()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Ticker

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AudioPlaybackService.tickInterval)
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard let player else { return }

        guard player.isPlaying else {
            // `pause()` and `stop()` both cancel the ticker first, so the only way to
            // arrive here is the item finishing on its own.
            stopTicking()
            player.currentTime = 0
            continuation.yield(.progress(0))
            continuation.yield(.finished)
            return
        }
        continuation.yield(.progress(player.currentTime))
    }

    // MARK: - Session

    /// Configures the session for playback *without* giving up the input route.
    ///
    /// `.playback` would be the natural choice, but replay happens while a paused
    /// `AudioRecordingService` still holds an `AVAudioEngine` with a tap on the input node.
    /// Dropping input out from under it means the engine may refuse to restart when the
    /// user resumes their take. `.playAndRecord` keeps input available across the whole
    /// record → replay → resume cycle; `.defaultToSpeaker` stops it playing out of the
    /// earpiece, which is what `.playAndRecord` does otherwise.
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    private func unload() {
        player?.stop()
        player = nil
        loadedURL = nil
    }
}
