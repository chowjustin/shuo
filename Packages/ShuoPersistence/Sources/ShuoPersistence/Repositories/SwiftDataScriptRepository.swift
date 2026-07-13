//
//  SwiftDataScriptRepository.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// Implements `ScriptRepository` (ShuoCore) using SwiftData's `ModelContext`. The only
// place a `ScriptEntity` is read from or written to storage — everything else sees
// `Script` via `ScriptMapper`.

import Foundation
