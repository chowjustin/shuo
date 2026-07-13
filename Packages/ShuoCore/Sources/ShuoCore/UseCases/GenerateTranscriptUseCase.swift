//
//  GenerateTranscriptUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: routes a `SpeechSource` to a `Transcript` — recordedAudio/importedMedia go
// through `SpeechTranscribing`, typedText short-circuits straight to the transcript with
// no transcription call. See ARCHITECTURE.md §3.2.1.

import Foundation
