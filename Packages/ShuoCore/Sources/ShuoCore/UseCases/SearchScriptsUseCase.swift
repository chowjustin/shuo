//
//  SearchScriptsUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: title search over already-fetched `[ScriptSummary]` — naive in-memory
// filtering, no `#Predicate`-driven fetch, per the expected dataset size. See
// ARCHITECTURE.md §3.3, §2.4.

import Foundation
