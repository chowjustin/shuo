//
//  ScriptRepository.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `ScriptRepository` — save / fetch(id:) / fetchSummaries() /
// search(query:) / delete(id:). Implemented by `SwiftDataScriptRepository` in
// ShuoPersistence; consumed only through this protocol by use cases and ViewModels
// (CLAUDE.md §4).

import Foundation
