//
//  FakeAIAvailabilityChecking.swift
//  ShuoTestSupport
//
//  Created by Justin Chow on 13/07/26.
//

// Fake conforming to `AIAvailabilityChecking` (ShuoCore), returning a scripted
// `AIAvailabilityStatus` (e.g. `.modelNotReady`, `.appleIntelligenceNotEnabled`).

import Foundation
import ShuoCore

/// Scripted `AIAvailabilityChecking` for tests.
///
/// Supports a *sequence* of statuses as well as a fixed one, so the poll-until-ready path
/// can be tested: `.modelNotReady` on the first call, `.available` on the next. The last
/// value repeats once the sequence is exhausted.
public actor FakeAIAvailabilityChecking: AIAvailabilityChecking {

    private var statuses: [AIAvailabilityStatus]
    private var index = 0

    public private(set) var callCount = 0

    public init(_ status: AIAvailabilityStatus = .available) {
        self.statuses = [status]
    }

    public init(sequence: [AIAvailabilityStatus]) {
        self.statuses = sequence.isEmpty ? [.available] : sequence
    }

    public func availability() async -> AIAvailabilityStatus {
        callCount += 1
        let status = statuses[min(index, statuses.count - 1)]
        index += 1
        return status
    }
}
