//
//  Script.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `Script` — the aggregate root persisted for a finished speech (title,
// purpose, transcript, patterns, key points, grammar suggestions, timestamps). Captures
// the full generated state, not just the raw transcript, so reopening a script needs no
// AI re-invocation. See ARCHITECTURE.md §3.3.

import Foundation
