//
//  ScriptEntity.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// SwiftData `@Model` class mirroring `Script`. Scalar fields as attributes;
// patterns/keyPoints/grammarSuggestions stored as Codable value arrays rather than
// separate relationship entities. See ARCHITECTURE.md §12.3. Stays inside
// ShuoPersistence — never crosses a package boundary (CLAUDE.md §6).

import Foundation
