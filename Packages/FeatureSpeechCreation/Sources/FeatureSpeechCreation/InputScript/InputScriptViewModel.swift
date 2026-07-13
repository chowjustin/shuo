//
//  InputScriptViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Composes three focused child ViewModels
// (`SpeakModeViewModel`, `WriteModeViewModel`, `AttachFileModeViewModel`) instead of one
// ViewModel with a dozen optional properties (CLAUDE.md §5). `hasValidContent` gates
// 'proceed to Transcript' as a pure function of the active mode's state. See
// ARCHITECTURE.md §3.1.2.

import Foundation
