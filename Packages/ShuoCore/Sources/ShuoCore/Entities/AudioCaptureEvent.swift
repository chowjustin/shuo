//
//  AudioCaptureEvent.swift
//  ShuoCore
//
//  Created by Justin Chow on 17/07/26.
//

import Foundation

/// A single update from an `AudioCapturing` session.
///
/// Everything an active capture session reports flows through one stream so that
/// waveform updates and system interruptions cannot race each other — see
/// ARCHITECTURE.md §3.1.3.
public enum AudioCaptureEvent: Sendable, Equatable {
    /// New amplitude samples since the previous tick, plus the session length so far.
    /// Emitted at roughly 10–20Hz so SwiftUI is not redrawn per audio buffer.
    case tick(amplitudes: [Float], duration: TimeInterval)

    /// The system suspended capture — an incoming call, or an audio route change such
    /// as headphones being unplugged. Audio captured up to this point is retained.
    case interrupted

    /// Capture stopped and cannot continue. Audio captured before the failure is
    /// retained and still recoverable via `finish()`.
    case failed(ShuoError)

    // MARK: DEBUG_LIVE_TRANSCRIPT — temporary; delete this case. See PR notes.
    //
    // The shipped design never displays the live transcript (ARCHITECTURE.md §3.1.3):
    // it is accumulated inside ShuoAudio and handed over once, via
    // `AudioRecording.liveTranscript`. This case exists only so a debug panel can
    // observe transcription working in real time. Removing it does not affect
    // `liveTranscript`, which is accumulated independently of this forwarding path.
    /// Best-effort live transcript so far. May revise previously reported text, since
    /// the speech model refines volatile results as more audio arrives.
    case transcript(String)
    // MARK: END DEBUG_LIVE_TRANSCRIPT
}
