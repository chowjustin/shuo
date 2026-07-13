//
//  SpeakModeViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Idle→recording→paused→recording→finished state machine,
// driven through `AudioCapturing` (ShuoCore) injected via the initializer — never a
// concrete `ShuoAudio` type (CLAUDE.md §4). See ARCHITECTURE.md §3.1.3.

import Foundation
