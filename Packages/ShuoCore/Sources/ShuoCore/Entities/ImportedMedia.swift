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
    /// The original URL from the file picker. Use `resolveURL()` for actual file access.
    public let fileURL: URL
    /// Security-scoped bookmark for persistent access across sessions. Nil for recordings/tests.
    public let bookmarkData: Data?
    public let kind: Kind
    public let originalFileName: String
    /// Duration in seconds. Nil for PDF or when unavailable.
    public let duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        bookmarkData: Data? = nil,
        kind: Kind,
        originalFileName: String,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.kind = kind
        self.originalFileName = originalFileName
        self.duration = duration
    }

    /// Resolves the security-scoped bookmark and starts access.
    /// Returns the accessible URL and a stop closure to call when done.
    /// Falls back to `fileURL` directly when no bookmark is stored (recordings, tests).
    public func resolveURL() throws -> (url: URL, stopAccessing: () -> Void) {
        guard let bookmarkData else {
            return (fileURL, {})
        }
        var isStale = false
        let resolved = try URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        )
        let didStart = resolved.startAccessingSecurityScopedResource()
        return (resolved, { if didStart { resolved.stopAccessingSecurityScopedResource() } })
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
