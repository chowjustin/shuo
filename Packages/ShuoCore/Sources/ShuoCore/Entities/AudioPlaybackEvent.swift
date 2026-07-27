//
//  AudioPlaybackEvent.swift
//  ShuoCore
//

import Foundation

/// A single update from an `AudioPlaying` session.
///
/// Mirrors `AudioCaptureEvent`: one ordered stream rather than a set of callbacks, so a
/// position update cannot be delivered after the `finished` that supersedes it.
public enum AudioPlaybackEvent: Sendable, Equatable {
    /// How far into the item playback has reached. Emitted at roughly 10Hz — enough for a
    /// playhead to read as continuous without redrawing SwiftUI per audio buffer.
    case progress(TimeInterval)

    /// Playback reached the end of the item on its own. Not emitted for a `pause()` or
    /// `stop()`, which the caller already knows about.
    case finished

    /// Playback could not start or could not continue.
    case failed(ShuoError)
}
