//
//  HomeViewModel.swift
//  FeatureHome
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Drives `HomeViewState` via `FetchScriptSummariesUseCase`
// and `SearchScriptsUseCase` (both from ShuoCore, injected through the initializer) —
// never a concrete `ShuoPersistence` type (CLAUDE.md §4).

import Foundation
import ShuoCore

@Observable
@MainActor
public final class HomeViewModel {
    public private(set) var state: HomeViewState = .loading

    public var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            search()
        }
    }

    private let fetchScriptSummaries: FetchScriptSummariesUseCase
    private let searchScripts: SearchScriptsUseCase

    private let deleteScript: DeleteScriptUseCase
    private var loadTask: Task<Void, Never>?

    public init(
        fetchScriptSummaries: FetchScriptSummariesUseCase,
        searchScripts: SearchScriptsUseCase,
        deleteScript: DeleteScriptUseCase
    ) {
        self.fetchScriptSummaries = fetchScriptSummaries
        self.searchScripts = searchScripts
        self.deleteScript = deleteScript
    }

    public func load() {
        run(showLoadingState: true) { [fetchScriptSummaries] in
            try await fetchScriptSummaries()
        }
    }


    public func delete(id: UUID) {
        Task {
            do {
                try await deleteScript(id: id)
                
                // Refresh list tanpa memunculkan loading state yang agresif
                if searchQuery.isEmpty {
                    run(showLoadingState: false) { [fetchScriptSummaries] in
                        try await fetchScriptSummaries()
                    }
                } else {
                    search()
                }
            } catch {
                // Di sini kamu bisa melempar error ke state jika ingin memunculkan banner error,
                // untuk sekarang kita cetak di console.
                print("Failed to delete script: \(error)")
            }
        }
    }

    private func search() {
        let query = searchQuery
        run(showLoadingState: false) { [searchScripts] in
            try await searchScripts(query: query)
        }
    }

    private func run(showLoadingState: Bool, _ fetch: @escaping () async throws -> [ScriptSummary]) {
        loadTask?.cancel()
        if showLoadingState { state = .loading }

        loadTask = Task {
            do {
                let summaries = try await fetch()
                
                guard !Task.isCancelled else { return }
                state = summaries.isEmpty ? .empty : .loaded(summaries)
            } catch {
                guard !Task.isCancelled else { return }
                state = .empty
            }
        }
    }
}
