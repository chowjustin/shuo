//
//  SpeechTranscribingRouter.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// `actor` conforming to `SpeechTranscribing` (ShuoCore); facade that picks between
// `SpeechAnalyzerTranscriptionService` and `LegacySpeechRecognitionService` at call time.

import Foundation
