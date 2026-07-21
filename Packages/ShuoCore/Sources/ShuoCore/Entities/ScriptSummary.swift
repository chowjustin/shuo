//
//  ScriptSummary.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

/// The Home list's view of a saved script: enough to render a row, and nothing more.
///
/// Deliberately excludes the transcript and key points. A speech transcript can run to
/// thousands of words, and loading fifty of them to draw fifty list rows would make the
/// list's cost scale with content the user cannot even see from there.
public struct ScriptSummary: Sendable, Identifiable, Equatable, Codable, Hashable {
    public let id: UUID
    public let title: String
    public let purpose: SpeechPurpose
    public let createdAt: Date
    /// Duration of the source recording, or nil for typed input.
    public let recordingDuration: TimeInterval?

    public init(
        id: UUID,
        title: String,
        purpose: SpeechPurpose,
        createdAt: Date,
        recordingDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.createdAt = createdAt
        self.recordingDuration = recordingDuration
    }
}
