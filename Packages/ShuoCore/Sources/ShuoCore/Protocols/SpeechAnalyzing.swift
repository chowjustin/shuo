//
//  SpeechAnalyzing.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `SpeechAnalyzing` — suggestPatterns / generateKeyPoints /
// refineTranscript / analyzeGrammar. Implemented by `FoundationModelSpeechAnalyzer` in
// ShuoAI; use cases depend only on this protocol, never on `import FoundationModels`
// directly. See ARCHITECTURE.md §3.2.4. `analyzeGrammar` stays defined but unused in v1
// (CLAUDE.md §8).

import Foundation
