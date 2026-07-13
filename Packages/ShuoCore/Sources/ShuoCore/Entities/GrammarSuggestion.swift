//
//  GrammarSuggestion.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `GrammarSuggestion` struct (originalPhrase, suggestedPhrase,
// explanation). Defined now so the persisted schema and `SpeechAnalyzing` protocol
// don't need a breaking change later, but unused in v1 — do not wire this into any use
// case or ViewModel unless explicitly asked to pick that work back up (CLAUDE.md §8, §11).

import Foundation
