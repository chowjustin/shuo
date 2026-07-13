//
//  AIAvailabilityChecking.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `AIAvailabilityChecking` — availability() async -> AIAvailabilityStatus.
// Implemented by `AIAvailabilityGate` in ShuoAI, wrapping
// `SystemLanguageModel.default.availability`.

import Foundation
