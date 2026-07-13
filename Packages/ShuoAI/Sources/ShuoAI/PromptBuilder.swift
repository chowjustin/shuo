//
//  PromptBuilder.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Centralizes prompt/instruction text for every `SpeechAnalyzing` call, keeping prompt
// wording reviewable and testable as data rather than buried in
// `FoundationModelSpeechAnalyzer`'s control flow (CLAUDE.md §8).

import Foundation
