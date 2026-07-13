//
//  ApplyPatternUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: (Transcript, SpeechPattern) -> (keyPoints, refinedTranscript), scoped to the
// newly selected pattern — a second, smaller AI call conditioned on the already-generated
// original transcript. See ARCHITECTURE.md §3.2.3.

import Foundation
