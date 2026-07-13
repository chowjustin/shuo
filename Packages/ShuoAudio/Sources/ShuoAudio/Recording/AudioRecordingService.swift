//
//  AudioRecordingService.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// `actor` conforming to `AudioCapturing` (ShuoCore); wraps the non-`Sendable`
// `AVAudioEngine`/recorder state, exposing async start()/pause()/resume()/finish() plus
// an `AsyncStream<[Float]>` amplitude stream throttled to ~10-20Hz for the waveform. See
// ARCHITECTURE.md §3.1.3.

import Foundation
