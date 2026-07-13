//
//  SuggestPatternsUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: transcript -> up to 3 `SpeechPattern`s via `SpeechAnalyzing`. The count is
// enforced by `@Guide(.count(3))` at the ShuoAI schema level, not truncated here.

import Foundation
