//
//  AudioRecording.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `AudioRecording` struct (id, fileURL, duration, waveformSamples,
// createdAt), produced by `AudioCapturing`. Distinct from the `AudioCapturing` protocol
// name — do not conflate the two (CLAUDE.md §12).

import Foundation

public struct AudioRecording: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// On-disk location of the captured audio. Always written, even when
    /// `liveTranscript` is populated — it is the fallback transcription source.
    public let fileURL: URL
    /// Length in seconds, derived from frames actually written to `fileURL`.
    public let duration: TimeInterval
    /// Normalized (0...1) amplitudes for the whole session, for waveform rendering.
    public let waveformSamples: [Float]
    public let createdAt: Date
    /// Transcript captured live while recording. Nil when live transcription was
    /// unavailable, unauthorized, or failed — callers then transcribe `fileURL`
    /// instead. Treat a populated value as an optimization, never a guarantee.
    public let liveTranscript: String?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        duration: TimeInterval,
        waveformSamples: [Float] = [],
        createdAt: Date = Date(),
        liveTranscript: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.duration = duration
        self.waveformSamples = waveformSamples
        self.createdAt = createdAt
        self.liveTranscript = liveTranscript
    }
}
