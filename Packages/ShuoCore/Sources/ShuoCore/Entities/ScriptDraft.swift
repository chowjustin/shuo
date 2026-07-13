//
//  ScriptDraft.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `ScriptDraft` — mutable in-flight state for the entire create/reopen
// flow, owned by `CreateScriptCoordinator`. `existingScriptID` is nil for a brand-new
// draft and set when reopening a saved script; that's what tells `SaveScriptUseCase`
// whether to insert or update. See ARCHITECTURE.md §6.

import Foundation
