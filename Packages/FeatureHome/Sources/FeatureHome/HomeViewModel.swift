//
//  HomeViewModel.swift
//  FeatureHome
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Drives `HomeViewState` via `FetchScriptSummariesUseCase`
// and `SearchScriptsUseCase` (both from ShuoCore, injected through the initializer) —
// never a concrete `ShuoPersistence` type (CLAUDE.md §4).

import Foundation
