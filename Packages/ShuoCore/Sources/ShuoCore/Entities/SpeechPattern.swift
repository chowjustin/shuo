//
//  SpeechPattern.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `SpeechPattern` struct (id, name, summary, outline) — the AI-suggested
// structural pattern surfaced by `SpeechAnalyzing`, mapped from ShuoAI's `@Generable`
// DTOs before reaching this layer.

import Foundation

public struct SpeechPattern: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let summary: String

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String
    ) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}
