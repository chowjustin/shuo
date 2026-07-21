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

    public init() {}

    public func importFile(from url: URL) async throws -> ImportedMedia {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Ordered cheapest-first, and type before size: a picked PDF should be reported
        // as the wrong kind of file, not as an oversized one.
        let kind = try mediaKind(for: url)
        try checkFileSize(url)

        let duration = await probeDuration(of: url)
        guard MediaLimits.isDurationAllowed(duration) else {
            throw ShuoError.mediaTooLong
        }
        // Checked here as well as in `GenerateTranscriptUseCase`, so all three limits report
        // at the same moment — at pick time, while the picker is still the thing the user is
        // looking at. The use-case check remains the real guarantee, since a recording never
        // passes through here.
        guard MediaLimits.isDurationLongEnough(duration) else {
            throw ShuoError.mediaTooShort
        }

        let bookmarkData = try createBookmark(url)

        return ImportedMedia(
            fileURL: url,
            bookmarkData: bookmarkData,
            kind: kind,
            originalFileName: url.lastPathComponent,
            duration: duration
        )
    }

    // MARK: - Helpers

    private func checkFileSize(_ url: URL) throws {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = attributes[.size] as? Int ?? 0
        guard MediaLimits.isFileSizeAllowed(fileSize) else {
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

    // The picker already filters to audio and video, so reaching the throwing branch
    // means the file arrived another way or carries a misleading extension. Unlike the
    // previous version this no longer defaults unknown types to `.audio` — that turned
    // "this file is not media" into an opaque transcription failure much later on.
    private func mediaKind(for url: URL) throws -> ImportedMedia.Kind {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            throw ShuoError.unsupportedMediaType
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        throw ShuoError.unsupportedMediaType
    }

    private func probeDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
