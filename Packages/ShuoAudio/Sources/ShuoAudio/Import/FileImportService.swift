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

        let sandboxURL = try copyToSandbox(url)
        let kind = mediaKind(for: url)
        let duration: TimeInterval? = kind != .pdf ? await probeDuration(of: sandboxURL) : nil

        return ImportedMedia(
            fileURL: sandboxURL,
            kind: kind,
            originalFileName: url.lastPathComponent,
            duration: duration
        )
    }

    // MARK: - Helpers

    // Copies the source file into `Application Support/Attachments/`, creating the
    // directory if needed. Returns the destination URL.
    private func copyToSandbox(_ source: URL) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let attachmentsDir = support.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: attachmentsDir,
            withIntermediateDirectories: true
        )

        let destination = attachmentsDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ShuoError.importFailed
        }
        return destination
    }

    // Maps the file's UTType to the domain `ImportedMedia.Kind`.
    private func mediaKind(for url: URL) -> ImportedMedia.Kind {
        guard
            let type = UTType(filenameExtension: url.pathExtension)
        else { return .audio }

        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        return .audio
    }

    // Returns the media duration in seconds via `AVAsset`, or nil on failure.
    private func probeDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
