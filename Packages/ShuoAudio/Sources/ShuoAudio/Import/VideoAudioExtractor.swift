//
//  VideoAudioExtractor.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// Extracts the audio track from a video attachment (`AVAssetReader`/
// `AVAssetExportSession`) before it's fed to the transcriber. Easy to miss when reading
// the acceptance criteria at a glance — flagged explicitly in CLAUDE.md §12.

import AVFoundation
import Foundation
import ShuoCore

/// Pulls the audio track out of a video file into a standalone m4a the transcriber can
/// read.
///
/// The output lands in the temporary directory and is the caller's to delete — see
/// `ExtractedAudio.cleanUp()`. Nothing here caches: a video is transcribed once, and
/// keeping a second copy of the user's media around afterwards would be both wasteful
/// and surprising.
struct VideoAudioExtractor {

    /// An extracted audio file plus the closure that removes it.
    struct ExtractedAudio {
        let url: URL
        /// Deletes the temporary file. Safe to call more than once.
        let cleanUp: @Sendable () -> Void
    }

    /// Extracts `sourceURL`'s audio track to a temporary m4a.
    ///
    /// - Throws: `ShuoError.audioExtractionFailed` when the asset has no audio track, is
    ///   unreadable, or the export fails.
    func extractAudio(from sourceURL: URL) async throws -> ExtractedAudio {
        let asset = AVURLAsset(url: sourceURL)

        // A video with no audio track is a user-facing situation, not a technical one —
        // a silent screen recording is easy to attach by accident, so it gets its own
        // check rather than surfacing later as an opaque export failure.
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !audioTracks.isEmpty else {
            throw ShuoError.audioExtractionFailed
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ShuoError.audioExtractionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("extracted-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw ShuoError.audioExtractionFailed
        }

        return ExtractedAudio(url: outputURL) {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}
