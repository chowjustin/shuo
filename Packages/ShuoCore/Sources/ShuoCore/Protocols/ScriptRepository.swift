//
//  ScriptRepository.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `ScriptRepository` — save / fetch(id:) / fetchSummaries() /
// search(query:) / delete(id:). Implemented by `SwiftDataScriptRepository` in ShuoPersistence; consumed
// only through this protocol by use cases and ViewModels (CLAUDE.md §4).

import Foundation

/// Storage for saved scripts, stated without reference to SwiftData.
///
/// This boundary is what keeps `@Model` types inside `ShuoPersistence` and lets the domain
/// be tested against an in-memory fake. It is also the seam where CloudKit sync could be
/// added later without a rearchitecture — though nothing should be built toward that now
/// (CLAUDE.md §11).
public protocol ScriptRepository: Sendable {
    /// Inserts `script`, or replaces the stored script with the same id.
    ///
    /// Idempotent by id, so a caller retrying after a failure cannot create duplicates.
    /// - Throws: `ShuoError.persistenceFailed`.
    func save(_ script: Script) async throws

    /// The full script for `id`, or nil when no such script exists.
    ///
    /// A missing script is nil rather than an error: reopening something that has been
    /// removed is an ordinary outcome, not a failure worth an error screen.
    /// - Throws: `ShuoError.persistenceFailed`.
    func fetch(id: UUID) async throws -> Script?

    /// Every saved script as a lightweight summary, newest first.
    /// - Throws: `ShuoError.persistenceFailed`.
    func fetchSummaries() async throws -> [ScriptSummary]

    /// Summaries whose title matches `query`, case-insensitively, newest first. A blank
    /// query returns everything, so the search field's empty state needs no special case
    /// at the call site.
    /// - Throws: `ShuoError.persistenceFailed`.
    func search(query: String) async throws -> [ScriptSummary]
    
    /// Deletes the script with the matching `id`.
    ///
    /// Silently succeeds if no script with the given ID exists, as the end goal
    /// (the script not being in the repository) is still met.
    /// - Throws: `ShuoError.persistenceFailed`.
    func delete(id: UUID) async throws
}
