//
//  FakeAudioRecordingDeleting.swift
//  ShuoTestSupport
//

import Foundation
import ShuoCore

/// `AudioRecordingDeleting` that records what it was asked to delete.
///
/// v1 removes a take once the speech is saved, and the take that has to be removed is the
/// one whose capture session already ended — which `AudioCapturing.discard()` cannot reach.
/// Asserting on `deleted` is how tests tell those two paths apart.
public actor FakeAudioRecordingDeleting: AudioRecordingDeleting {
    public private(set) var deleted: [AudioRecording] = []

    public init() {}

    public func delete(_ recording: AudioRecording) async {
        deleted.append(recording)
    }
}
