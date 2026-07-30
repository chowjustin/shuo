//
//  AudioRecordingFileStore.swift
//  ShuoAudio
//

import Foundation
import ShuoCore

/// `AudioRecordingDeleting` backed by the file system.
///
/// Stateless, so one instance is shared for the app's lifetime — unlike
/// `AudioRecordingService`, which is single-use by contract.
public struct AudioRecordingFileStore: AudioRecordingDeleting {
    public init() {}

    public func delete(_ recording: AudioRecording) async {
        // Already-gone is the outcome the caller wanted, and there is nothing a user could
        // do about a failure here, so this is deliberately best-effort (CLAUDE.md §5).
        try? FileManager.default.removeItem(at: recording.fileURL)
    }
}
