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
