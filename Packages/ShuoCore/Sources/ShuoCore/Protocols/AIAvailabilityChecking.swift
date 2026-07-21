//
//  AIAvailabilityChecking.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// Reports whether on-device generation can run right now.
///
/// Queried before starting an analysis so a model that isn't ready produces the loading
/// state rather than a mid-flight generation error the user can do nothing about
/// (CLAUDE.md §8).
public protocol AIAvailabilityChecking: Sendable {
    /// The model's current availability. Not cached — assets can finish downloading, and
    /// Apple Intelligence can be switched on, while the app is running.
    func availability() async -> AIAvailabilityStatus
}
