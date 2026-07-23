//
//  SwiftDataScriptRepository.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// Implements `ScriptRepository` (ShuoCore) using SwiftData's `ModelContext`. The only
// place a `ScriptEntity` is read from or written to storage — everything else sees
// `Script` via `ScriptMapper`.

import Foundation
import ShuoCore
import SwiftData

/// SwiftData-backed script storage.
///
/// A `@ModelActor`, which is what makes this safe under Swift 6 strict concurrency:
/// `ModelContext` is not `Sendable`, so the actor owns one privately and every operation
/// runs on the actor's executor. Nothing outside ever touches the context, and no
/// `@unchecked Sendable` is needed anywhere (CLAUDE.md §6).
///
/// Every SwiftData error is caught here and rethrown as `ShuoError.persistenceFailed`, so
/// nothing above this package needs to import SwiftData to handle a failure (CLAUDE.md §5).
@ModelActor
public actor SwiftDataScriptRepository: ScriptRepository {

    public func save(_ script: Script) async throws {
        do {
            if let existing = try existingEntity(id: script.id) {
                ScriptMapper.apply(script, to: existing)
            } else {
                modelContext.insert(ScriptMapper.toEntity(script))
            }
            try modelContext.save()
        } catch {
            throw ShuoError.persistenceFailed
        }
    }

    public func fetch(id: UUID) async throws -> Script? {
        do {
            guard let entity = try existingEntity(id: id) else { return nil }
            return try ScriptMapper.toDomain(entity)
        } catch let error as ShuoError {
            throw error
        } catch {
            throw ShuoError.persistenceFailed
        }
    }

    public func fetchSummaries() async throws -> [ScriptSummary] {
        try summaries(matching: nil)
    }

    public func search(query: String) async throws -> [ScriptSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank query means "no filter" rather than "match nothing", so the search
        // field's empty state needs no special case at the call site.
        guard !trimmed.isEmpty else { return try summaries(matching: nil) }
        return try summaries(matching: trimmed)
    }

    // 👇 Tambahkan implementasi fungsi delete(id:) di sini
    public func delete(id: UUID) async throws {
        do {
            if let entity = try existingEntity(id: id) {
                modelContext.delete(entity)
                try modelContext.save()
            }
        } catch {
            throw ShuoError.persistenceFailed
        }
    }

    // MARK: - Helpers

    /// Newest-first summaries, optionally filtered by title.
    ///
    /// Uses `propertiesToFetch` so a list of fifty scripts doesn't drag fifty full
    /// transcripts into memory to draw fifty rows — the reason `ScriptSummary` exists at
    /// all. Only the properties listed here may be read from the results; anything else
    /// would silently fault the rest of the row back in and undo the saving.
    private func summaries(matching titleQuery: String?) throws -> [ScriptSummary] {
        var descriptor = FetchDescriptor<ScriptEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let titleQuery {
            descriptor.predicate = #Predicate<ScriptEntity> { entity in
                entity.title.localizedStandardContains(titleQuery)
            }
        }
        descriptor.propertiesToFetch = [
            \.id, \.title, \.purposeRawValue, \.createdAt, \.recordingDuration,
        ]

        do {
            return try modelContext.fetch(descriptor).map(ScriptMapper.toSummary)
        } catch let error as ShuoError {
            throw error
        } catch {
            throw ShuoError.persistenceFailed
        }
    }

    private func existingEntity(id: UUID) throws -> ScriptEntity? {
        // The predicate must compare against a local copy — `#Predicate` captures values,
        // and referencing the parameter through `self` would not compile.
        let target = id
        var descriptor = FetchDescriptor<ScriptEntity>(
            predicate: #Predicate { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
