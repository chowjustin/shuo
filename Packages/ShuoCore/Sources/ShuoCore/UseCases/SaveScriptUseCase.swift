//
//  SaveScriptUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: `ScriptDraft` -> persisted `Script`, insert or update depending on whether
// `existingScriptID` is set. Delegates to `ScriptRepository`.

import Foundation
