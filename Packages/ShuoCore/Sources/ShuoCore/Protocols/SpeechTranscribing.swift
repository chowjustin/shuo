//
//  SpeechTranscribing.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `SpeechTranscribing` — transcribe(_:) async throws -> String.
// Implemented by `SpeechTranscribingRouter` in ShuoAudio, which picks between the
// SpeechAnalyzer- and SFSpeechRecognizer-backed implementations.

import Foundation
