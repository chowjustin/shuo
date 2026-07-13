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
