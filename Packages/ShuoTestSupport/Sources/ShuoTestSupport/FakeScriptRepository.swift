//
//  FakeScriptRepository.swift
//  ShuoTestSupport
//
//  Created by Justin Chow on 13/07/26.
//

// In-memory fake conforming to `ScriptRepository` (ShuoCore), for domain/ViewModel tests
// that need save/fetch/search without real SwiftData.

import Foundation
import ShuoCore

/// In-memory `ScriptRepository` for tests.
///
/// An actor so stored state and call recording are race-free. Mirrors the real
/// repository's observable contract — idempotent save by id, nil for a missing fetch,
/// newest-first ordering, blank query returns everything — so a test passing against this
/// fake means something about the real implementation too. `SwiftDataScriptRepositoryTests`
/// asserts the same contract against actual SwiftData.
public actor FakeScriptRepository: ScriptRepository {

    private var storage: [UUID: Script] = [:]
    /// Injected failure, applied to every method. Set to exercise error paths.
    private var error: ShuoError?

    /// Delay applied before every method's effect lands. Non-zero lets a test observe the
    /// in-flight state, or attempt to cancel before the write happens — which is how the
    /// analysis view model's "an in-flight save survives cancellation" behavior gets
    /// tested deterministically.
    private var delay: Duration

    public private(set) var saveCount = 0
    public private(set) var fetchedIDs: [UUID] = []
    public private(set) var searchQueries: [String] = []

    /// Every stored script, newest first.
    public var scripts: [Script] {
        storage.values.sorted { $0.createdAt > $1.createdAt }
    }

    public init(
        scripts: [Script] = [],
        throwing error: ShuoError? = nil,
        after delay: Duration = .zero
    ) {
        self.storage = Dictionary(
            scripts.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        self.error = error
        self.delay = delay
    }

    public func setError(_ newError: ShuoError?) {
        error = newError
    }

    public func setDelay(_ newDelay: Duration) {
        delay = newDelay
    }

    // MARK: - ScriptRepository

    public func save(_ script: Script) async throws {
        try await waitIfNeeded()
        try failIfNeeded()
        saveCount += 1
        storage[script.id] = script
    }

    public func fetch(id: UUID) async throws -> Script? {
        try await waitIfNeeded()
        try failIfNeeded()
        fetchedIDs.append(id)
        return storage[id]
    }

    public func fetchSummaries() async throws -> [ScriptSummary] {
        try await waitIfNeeded()
        try failIfNeeded()
        return scripts.map(\.summary)
    }

    public func search(query: String) async throws -> [ScriptSummary] {
        try await waitIfNeeded()
        try failIfNeeded()
        searchQueries.append(query)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return scripts.map(\.summary) }
        return scripts
            .filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
            .map(\.summary)
    }

    private func failIfNeeded() throws {
        if let error { throw error }
    }

    private func waitIfNeeded() async throws {
        guard delay > .zero else { return }
        // A cancelled sleep throws, so a cancelled caller never completes the write — which
        // is exactly what a test asserting that a save *survives* cancellation needs to be
        // able to distinguish.
        try await Task.sleep(for: delay)
    }
}
