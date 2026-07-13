//
//  AIAvailabilityGate.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Conforms to `AIAvailabilityChecking` (ShuoCore); wraps
// `SystemLanguageModel.default.availability`. For v1, only needs to handle
// `.modelNotReady` (poll/retry with the Loading UI) and `.appleIntelligenceNotEnabled`
// (actionable Settings prompt) gracefully — `.deviceNotEligible` is a hard block
// enforced earlier, at onboarding. See ARCHITECTURE.md §3.2.4, CLAUDE.md §8.

import Foundation
