//
//  ShuoError.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain error enum: transcriptionFailed, aiUnavailable, contextWindowExceeded,
// importFailed, persistenceFailed, etc. Data-layer failures (SwiftData, FoundationModels,
// AVFoundation errors) get caught at the package boundary and re-thrown as one of these
// cases — Feature packages and ViewModels never catch an Apple-framework error type
// directly (CLAUDE.md §5).

import Foundation
