//
//  RegenerateKeyPointsUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: edited transcript -> updated key points. Debouncing and `Task` cancellation
// for rapid edits is the caller's (ViewModel's) responsibility, not this use case's —
// see CLAUDE.md §6 on cancellation.

import Foundation
