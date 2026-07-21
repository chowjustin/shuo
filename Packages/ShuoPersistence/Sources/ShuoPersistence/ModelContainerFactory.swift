//
//  ModelContainerFactory.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// Builds the SwiftData `Schema` + `ModelContainer`. The single source of truth for the
// schema — the app uses it in place, and tests use it with `isStoredInMemoryOnly: true`
// so the two can never drift apart (CLAUDE.md §7).

import Foundation
import ShuoCore
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// One factory for both production and tests, on purpose. A test that declared its own
/// `Schema` would keep passing after a production model change it no longer matches —
/// exactly the drift this indirection exists to prevent (CLAUDE.md §7).
public enum ModelContainerFactory {

    /// Every `@Model` type the app persists.
    public static var schema: Schema {
        Schema([ScriptEntity.self])
    }

    /// - Parameter isStoredInMemoryOnly: True in tests, so each run starts from an empty
    ///   store and nothing touches the simulator's disk.
    /// - Throws: `ShuoError.persistenceFailed` — SwiftData's own error type is caught at
    ///   this boundary so nothing above ShuoPersistence has to import SwiftData to handle
    ///   a failure (CLAUDE.md §5).
    public static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw ShuoError.persistenceFailed
        }
    }
}
