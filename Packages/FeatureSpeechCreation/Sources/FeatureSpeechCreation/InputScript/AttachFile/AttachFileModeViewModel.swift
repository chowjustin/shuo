//
//  AttachFileModeViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. idle → selected → processing → ready state machine, driven
// through `FileImporting` (ShuoCore) injected via the initializer. See
// ARCHITECTURE.md §3.1.5.

import Foundation
