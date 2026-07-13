//
//  FoundationModelSpeechAnalyzer.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Conforms to `SpeechAnalyzing` (ShuoCore). Owns the `LanguageModelSession`(s),
// prewarm(), and `streamResponse()` usage for progressive rendering. Prompt/instruction
// text is centralized in `PromptBuilder`, not inline here (CLAUDE.md §8). Gets minimal,
// mostly manual/integration test coverage — see ARCHITECTURE.md §8.

import Foundation
