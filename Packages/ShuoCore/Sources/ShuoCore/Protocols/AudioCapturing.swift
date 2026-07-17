//
//  AudioCapturing.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `AudioCapturing` — start()/pause()/resume()/finish() -> AudioRecording,
// plus an amplitude stream for the waveform. Implemented by the `AudioRecordingService`
// actor in ShuoAudio; lets ViewModel tests inject a fake instead of touching real
// hardware. See ARCHITECTURE.md §3.1.3.

import Foundation

/// A microphone capture session.
///
/// One instance is one session: after `finish()` or `discard()`, `events` completes and
/// the instance must not be reused. Compose a new one per recording.
public protocol AudioCapturing: Sendable {
    /// Everything the session reports, in order. Single-consumer — iterating from more
    /// than one task splits events between them rather than duplicating them. Completes
    /// after `finish()` or `discard()`.
    var events: AsyncStream<AudioCaptureEvent> { get }

    /// Best-effort warm-up: audio session configuration and on-device model assets.
    /// Safe to call speculatively (e.g. when the UI appears) and safe to skip entirely —
    /// `start()` performs any preparation `prepare()` did not finish. Never throws;
    /// preparation failures surface at `start()`, where the user can be told.
    func prepare() async

    /// Begins capture.
    /// - Precondition: microphone permission is granted. Callers gate on
    ///   `MicrophonePermissionProviding` first; this throws
    ///   `ShuoError.microphonePermissionDenied` if they did not.
    func start() async throws

    /// Suspends capture, retaining audio captured so far.
    func pause() async throws

    /// Continues a paused session. Duration and waveform resume from where they stopped.
    func resume() async throws

    /// Ends the session and returns what was captured.
    /// - Throws: `ShuoError.recordingFailed` if nothing usable was captured.
    func finish() async throws -> AudioRecording

    /// Ends the session and deletes the captured audio. Never throws — this is the
    /// teardown path, and a caller abandoning a recording has no use for an error.
    func discard() async
}
