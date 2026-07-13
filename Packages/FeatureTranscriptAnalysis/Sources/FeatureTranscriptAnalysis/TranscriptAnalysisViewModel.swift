//
//  TranscriptAnalysisViewModel.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Owns the debounced edit → `RegenerateKeyPointsUseCase`
// `Task` (stored and explicitly cancelled before every replacement — CLAUDE.md §6),
// pattern selection via `ApplyPatternUseCase`, and save via `SaveScriptUseCase`, all
// injected through the initializer.

import Foundation
