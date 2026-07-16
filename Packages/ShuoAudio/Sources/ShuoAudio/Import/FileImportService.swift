//
//  FileImportService.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

import AVFoundation
import Foundation
import ShuoCore
import UniformTypeIdentifiers

public struct FileImportService: FileImporting {

    static let maxFileSizeBytes: Int = 20 * 1_024 * 1_024 // 20 MB

    public init() {}

    public func importFile(from url: URL) async throws -> ImportedMedia {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try checkFileSize(url)

        let bookmarkData = try createBookmark(url)
        let kind = mediaKind(for: url)
        let duration: TimeInterval? = kind != .pdf ? await probeDuration(of: url) : nil

        return ImportedMedia(
            fileURL: url,
            bookmarkData: bookmarkData,
            kind: kind,
            originalFileName: url.lastPathComponent,
            duration: duration
        )
    }

    // MARK: - Helpers

    // Throws `ShuoError.fileTooLarge` if the file exceeds `maxFileSizeBytes`.
    private func checkFileSize(_ url: URL) throws {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = attributes[.size] as? Int ?? 0
        if fileSize > Self.maxFileSizeBytes {
            throw ShuoError.fileTooLarge
        }
    }

    // Creates a security-scoped bookmark so the file can be accessed in future sessions.
    private func createBookmark(_ url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw ShuoError.importFailed
        }
    }

    // Maps the file's UTType to the domain `ImportedMedia.Kind`.
    private func mediaKind(for url: URL) -> ImportedMedia.Kind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        return .audio
    }

    // Returns the media duration in seconds via `AVAsset`, or nil on failure.
    private func probeDuration(of url: URL) async -> TimeInterval? {
        let asset = AVAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
