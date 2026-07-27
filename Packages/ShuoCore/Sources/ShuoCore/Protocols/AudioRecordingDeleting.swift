//
//  AudioRecordingDeleting.swift
//  ShuoCore
//

import Foundation

/// Removes a finished recording's audio from disk.
///
/// Separate from `AudioCapturing` because the two have different lifetimes: a capture
/// session is retired by `finish()`, and the file it produced outlives it — through
/// transcription, through the analysis screen, and back again if the user returns to edit
/// their input. Deleting it is therefore something the flow does *after* the session that
/// wrote it is long gone, and `AudioCapturing.discard()` cannot reach it.
///
/// v1 keeps no recording after the speech is saved (ARCHITECTURE.md §6): the transcript is
/// the artifact, and audio the user cannot play back from the library is only storage they
/// have no way to reclaim.
public protocol AudioRecordingDeleting: Sendable {
    /// Deletes the audio behind `recording`. Idempotent, and never throws — a file that is
    /// already gone is the outcome the caller wanted, and a failure here is not something
    /// the user can act on.
    func delete(_ recording: AudioRecording) async
}
