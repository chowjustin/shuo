//
//  ImportedMedia.swift
//  ShuoCore
//

import Foundation

public struct ImportedMedia: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case audio
        case video
        case pdf
    }

    public let id: UUID
    public let fileURL: URL
    public let kind: Kind
    public let originalFileName: String
    /// Duration in seconds. Nil for PDF or when unavailable.
    public let duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        kind: Kind,
        originalFileName: String,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.kind = kind
        self.originalFileName = originalFileName
        self.duration = duration
    }

    /// "m:ss.d" formatted string, e.g. "1:23.7". Nil when duration is unavailable or zero.
    public var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let decimal = Int((duration * 10).rounded()) % 10
        return "\(minutes):\(String(format: "%02d", seconds)).\(decimal)"
    }
}
