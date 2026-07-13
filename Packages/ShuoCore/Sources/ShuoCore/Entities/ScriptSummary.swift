//
//  ScriptSummary.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `ScriptSummary` — lightweight Home-list projection (id, title, purpose,
// createdAt, recordingDuration), fetched instead of full `Script` objects so the list
// stays fast regardless of transcript size. See ARCHITECTURE.md §3.3.

import Foundation
