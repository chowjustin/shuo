//
//  HomeViewModelTests.swift
//  FeatureHomeTests
//
//  Created by Justin Chow on 13/07/26.
//

// PLACEHOLDER — this file contains no tests.
//
// Blocked on `HomeViewModel` itself, which is still an empty stub, as are `HomeViewState`,
// `ScriptRowView`, `SearchScriptsUseCase` and `FetchScriptSummariesUseCase`. When those
// land, this becomes a `@MainActor` suite injecting `FakeScriptRepository` and asserting
// state transitions plus case-insensitive search filtering (ARCHITECTURE.md §8).
//
// Kept as a marker rather than deleted, but stated as unbuilt: an earlier version of this
// comment described the coverage in the present tense, which made a file listing report
// the Home feature as tested when neither it nor its tests exist.

import Foundation
import Testing
import ShuoCore
import ShuoTestSupport
@testable import FeatureHome

@MainActor
@Suite("Home view model")
struct HomeViewModelTests {

    private func script(title: String, createdAt: Date) -> Script {
        Script(
            title: title,
            purpose: .inform,
            transcript: Transcript(original: "placeholder"),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeViewModel(scripts: [Script] = []) -> HomeViewModel {
        let repository = FakeScriptRepository(scripts: scripts)
        return HomeViewModel(
            fetchScriptSummaries: FetchScriptSummariesUseCase(repository: repository),
            searchScripts: SearchScriptsUseCase(repository: repository),
            deleteScript: DeleteScriptUseCase(repository: repository)
        )
    }

    /// Polls until `condition` holds, so tests wait on observable state rather than on
    /// a fixed sleep. `load()`/`search()` run in a detached task with no completion
    /// handle to await.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for the expected state")
    }

    @Test("starts in .loading before load() is called")
    func startsLoading() {
        let viewModel = makeViewModel()
        #expect(viewModel.state == .loading)
    }

    @Test("loading with no saved scripts settles on .empty")
    func loadsEmptyWhenNoScripts() async throws {
        let viewModel = makeViewModel()

        viewModel.load()
        try await waitUntil { viewModel.state != .loading }

        #expect(viewModel.state == .empty)
    }

    @Test("loading with saved scripts settles on .loaded with every summary")
    func loadsEveryScript() async throws {
        let viewModel = makeViewModel(scripts: [
            script(title: "Graduation Speech", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            script(title: "Wedding Toast", createdAt: Date(timeIntervalSince1970: 1_700_003_600)),
        ])

        viewModel.load()
        try await waitUntil { viewModel.state != .loading }

        guard case .loaded(let summaries) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(Set(summaries.map(\.title)) == ["Graduation Speech", "Wedding Toast"])
    }

    @Test("typing a query filters the list case-insensitively, on every keystroke")
    func searchQueryFiltersCaseInsensitively() async throws {
        let viewModel = makeViewModel(scripts: [
            script(title: "Graduation Speech", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            script(title: "Wedding Toast", createdAt: Date(timeIntervalSince1970: 1_700_003_600)),
        ])
        viewModel.load()
        try await waitUntil { viewModel.state != .loading }

        viewModel.searchQuery = "grad"
        try await waitUntil {
            if case .loaded(let summaries) = viewModel.state { return summaries.count == 1 }
            return false
        }

        guard case .loaded(let summaries) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(summaries.map(\.title) == ["Graduation Speech"])
    }

    @Test("a query matching nothing lands on .empty rather than an empty .loaded list")
    func noMatchesIsEmptyState() async throws {
        let viewModel = makeViewModel(scripts: [
            script(title: "Graduation Speech", createdAt: .now),
        ])
        viewModel.load()
        try await waitUntil { viewModel.state != .loading }

        viewModel.searchQuery = "nonexistent"
        try await waitUntil { viewModel.state == .empty }

        #expect(viewModel.state == .empty)
    }

    @Test("clearing the query restores the full, unfiltered list")
    func clearingQueryRestoresFullList() async throws {
        let viewModel = makeViewModel(scripts: [
            script(title: "Graduation Speech", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            script(title: "Wedding Toast", createdAt: Date(timeIntervalSince1970: 1_700_003_600)),
        ])
        viewModel.load()
        try await waitUntil { viewModel.state != .loading }

        viewModel.searchQuery = "grad"
        try await waitUntil {
            if case .loaded(let summaries) = viewModel.state { return summaries.count == 1 }
            return false
        }

        viewModel.searchQuery = ""
        try await waitUntil {
            if case .loaded(let summaries) = viewModel.state { return summaries.count == 2 }
            return false
        }

        guard case .loaded(let summaries) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(summaries.count == 2)
    }

    @Test("a fetch failure is treated the same as an empty library")
    func fetchFailureFallsBackToEmpty() async throws {
        let repository = FakeScriptRepository(throwing: .persistenceFailed)
        let viewModel = HomeViewModel(
            fetchScriptSummaries: FetchScriptSummariesUseCase(repository: repository),
            searchScripts: SearchScriptsUseCase(repository: repository),
            // 👇 Inject DeleteScriptUseCase
            deleteScript: DeleteScriptUseCase(repository: repository)
        )

        viewModel.load()
        try await waitUntil { viewModel.state != .loading }

        #expect(viewModel.state == .empty)
    }

    @Test("a fast typer's earlier, slower request never overwrites the later one")
    func laterQueryWinsOverSlowerEarlierOne() async throws {
        let repository = FakeScriptRepository(
            scripts: [
                script(title: "Graduation Speech", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
                script(title: "Wedding Toast", createdAt: Date(timeIntervalSince1970: 1_700_003_600)),
            ],
            after: .milliseconds(50)
        )
        let viewModel = HomeViewModel(
            fetchScriptSummaries: FetchScriptSummariesUseCase(repository: repository),
            searchScripts: SearchScriptsUseCase(repository: repository),
            deleteScript: DeleteScriptUseCase(repository: repository)
        )
        viewModel.load()
        try await waitUntil(timeout: .seconds(1)) { viewModel.state != .loading }

        // "grad" starts a slow, in-flight search; "wedding" starts a second one
        // before the first can land. If cancellation weren't wired up, "grad"'s
        // response could still arrive after "wedding"'s and clobber it.
        viewModel.searchQuery = "grad"
        viewModel.searchQuery = "wedding"

        try await waitUntil(timeout: .seconds(1)) {
            if case .loaded(let summaries) = viewModel.state { return summaries.count == 1 }
            return false
        }

        guard case .loaded(let summaries) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(summaries.map(\.title) == ["Wedding Toast"])
    }
}
