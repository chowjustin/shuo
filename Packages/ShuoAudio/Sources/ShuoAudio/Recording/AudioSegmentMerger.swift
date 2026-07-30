//
//  AudioSegmentMerger.swift
//  ShuoAudio
//

import AVFoundation
import Foundation
import OSLog
import ShuoCore

/// Joins the pieces a paused-and-resumed recording is written in back into one file.
///
/// `AudioRecordingService` closes its `.m4a` every time the user pauses, because an AAC
/// file that is still open is not yet a valid file to read — closing it is what makes the
/// take replayable mid-session. The cost of that is a take spread across several files,
/// and everything downstream (transcription, playback, the saved recording) wants exactly
/// one. This puts them back together.
///
/// Pure translation over AVFoundation with no state of its own, so it stays a static
/// helper rather than another actor: the caller is already isolated.
enum AudioSegmentMerger {
    private static let log = Logger(subsystem: "com.seven.shuo", category: "AudioSegmentMerger")

    /// Concatenates `segments`, in order, into a single `.m4a` at `destination`.
    ///
    /// - Throws: `ShuoError.recordingFailed` if no segment carried a readable audio track
    ///   or the export failed. Merging is never the user's fault and there is nothing for
    ///   them to do about it, so the failure is deliberately opaque and logged here — the
    ///   underlying AVFoundation error exists nowhere else (CLAUDE.md §5).
    static func merge(_ segments: [URL], into destination: URL) async throws {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ShuoError.recordingFailed
        }

        var cursor = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment)
            do {
                guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                    // A segment can legitimately be empty — pausing immediately after
                    // resuming writes no frames — so this is skipped rather than fatal.
                    continue
                }
                let duration = try await asset.load(.duration)
                guard duration > .zero else { continue }
                try track.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: cursor
                )
                cursor = cursor + duration
            } catch {
                log.error("Segment could not be read: \(error.localizedDescription, privacy: .public)")
                throw ShuoError.recordingFailed
            }
        }

        guard cursor > .zero else { throw ShuoError.recordingFailed }

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ShuoError.recordingFailed
        }

        try? FileManager.default.removeItem(at: destination)
        do {
            try await export.export(to: destination, as: .m4a)
        } catch {
            log.error("Segments could not be merged: \(error.localizedDescription, privacy: .public)")
            throw ShuoError.recordingFailed
        }
    }
}
