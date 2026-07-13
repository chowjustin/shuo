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
