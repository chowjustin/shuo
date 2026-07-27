//
//  AudioRecordingService.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// `actor` conforming to `AudioCapturing` (ShuoCore); wraps the non-`Sendable`
// `AVAudioEngine`/recorder state, exposing async start()/pause()/resume()/finish() plus
// an `AsyncStream<[Float]>` amplitude stream throttled to ~10-20Hz for the waveform. See
// ARCHITECTURE.md §3.1.3.

import AVFoundation
import Foundation
import OSLog
import ShuoCore

/// `AudioCapturing` backed by `AVAudioEngine`.
///
/// One tap on the input node feeds three consumers, so audio is captured once:
/// an `AVAudioFile` on disk, the waveform/duration event stream, and a
/// `LiveTranscriptionSession`. The file is always written even when live transcription
/// succeeds — it is what makes transcription recoverable if the live pass failed.
///
/// A take is written as one file *per run of recording*, not one file per session: an AAC
/// file that is still open for writing has no index and cannot be read back, so pausing
/// closes the current segment and resuming opens the next. That is what makes
/// `previewURL()` — replaying a take mid-session — possible at all. `AudioSegmentMerger`
/// puts the pieces back together, and the common case of a single pause never merges
/// anything because there is only ever one segment.
///
/// Kept as thin as it can be: the only real logic lives in `WaveformSampler`, which is
/// pure and tested. This type is verified by hand on a device (CLAUDE.md §7).
public actor AudioRecordingService: AudioCapturing {

    /// ~85ms of audio at 48kHz, so ticks arrive at roughly 12Hz — inside the 10–20Hz
    /// the waveform wants, without a separate throttle.
    private static let tapBufferSize: AVAudioFrameCount = 4096

    /// Capture failures become an opaque `ShuoError.recordingFailed` at this boundary, by
    /// design — the domain must not leak AVFoundation errors (CLAUDE.md §5). That leaves
    /// nothing to debug from a bug report, so the underlying error is logged here first.
    /// Filter Console or the Xcode console by subsystem `com.seven.shuo`.
    private static let log = Logger(subsystem: "com.seven.shuo", category: "AudioRecording")

    private enum State {
        case idle
        case recording
        case paused
        case ended
    }

    public nonisolated let events: AsyncStream<AudioCaptureEvent>
    private let eventContinuation: AsyncStream<AudioCaptureEvent>.Continuation

    private let engine = AVAudioEngine()
    private let transcription: LiveTranscriptionSession

    private var state: State = .idle
    /// The segment currently open for writing, if any. Closed on every pause.
    private var file: AVAudioFile?
    private var fileURL: URL?
    /// Segments closed so far, in capture order.
    private var segmentURLs: [URL] = []
    /// A merged copy of `segmentURLs` handed out by `previewURL()`, and the segment count
    /// it was built from — the cache key, since any further recording invalidates it.
    private var previewFileURL: URL?
    private var previewSegmentCount = 0
    private var recordingFormat: AVAudioFormat?
    private var framesWritten: AVAudioFramePosition = 0
    private var waveformSamples: [Float] = []

    private var processingTask: Task<Void, Never>?
    private var disruptionTask: Task<Void, Never>?
    private var observerTokens: [any NSObjectProtocol] = []
    private var isPrepared = false

    public init() {
        let (events, eventContinuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
        self.events = events
        self.eventContinuation = eventContinuation

        // DEBUG_LIVE_TRANSCRIPT — temporary; restore to `LiveTranscriptionSession()` and
        // delete this closure. It forwards live text to the event stream purely so a
        // debug panel can watch transcription work; the shipped design reads the
        // transcript once, from `finish()`.
        self.transcription = LiveTranscriptionSession { text in
            eventContinuation.yield(.transcript(text))
        }
        // END DEBUG_LIVE_TRANSCRIPT
    }

    // MARK: - AudioCapturing

    public func prepare() async {
        guard !isPrepared, state == .idle else { return }
        isPrepared = true
        // Configure the session first: the hardware sample rate is not meaningful until
        // it is active, and asset installation is the slow part worth starting early.
        try? configureSession()
        await transcription.prepare()
    }

    public func start() async throws {
        guard state == .idle else { return }

        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw ShuoError.microphonePermissionDenied
        }

        do {
            try configureSession()

            let inputNode = engine.inputNode
            let hardwareFormat = inputNode.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0 else { throw ShuoError.recordingFailed }

            // Speech is mono; recording one channel halves the file and matches what the
            // transcriber wants anyway.
            guard let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else { throw ShuoError.recordingFailed }

            self.recordingFormat = recordingFormat
            try openSegment()

            // The tap runs on a realtime audio thread and cannot touch actor state.
            // It extracts plain `[Float]` (Sendable) and hands them over through a
            // stream, which preserves ordering — spawning a Task per buffer would not.
            let (chunks, chunkContinuation) = AsyncStream.makeStream(of: [Float].self)
            inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: hardwareFormat) { buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                chunkContinuation.yield(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
            }
            processingTask = Task { [weak self] in
                for await chunk in chunks {
                    await self?.process(chunk)
                }
            }

            // Before starting the engine, not after: this is what may show the speech
            // authorization prompt, and audio recorded while a modal is up would be a
            // few seconds of the user reading an alert rather than speaking.
            await transcription.start(inputFormat: recordingFormat)

            engine.prepare()
            try engine.start()

            observeDisruptions()
            state = .recording
        } catch let error as ShuoError {
            Self.log.error("Recording could not start: \(String(describing: error), privacy: .public)")
            await tearDown(deletingFiles: true)
            throw error
        } catch {
            // The one place the real AVFoundation error exists before it is flattened.
            Self.log.error("Recording could not start: \(error.localizedDescription, privacy: .public) — \(String(describing: error), privacy: .public)")
            await tearDown(deletingFiles: true)
            throw ShuoError.recordingFailed
        }
    }

    public func pause() async throws {
        guard state == .recording else { return }
        engine.pause()
        state = .paused
        // Closing the segment is what turns the audio so far into a file that can be read
        // back — see `previewURL()`.
        sealCurrentSegment()
    }

    public func resume() async throws {
        guard state == .paused else { return }
        do {
            // Reconfigured rather than merely reactivated: replaying the take switches the
            // shared session to `.playAndRecord` (see `AudioPlaybackService`), and this is
            // where the recording category is claimed back.
            try configureSession()
            try openSegment()
            try engine.start()
            state = .recording
        } catch {
            Self.log.error("Recording could not resume: \(error.localizedDescription, privacy: .public)")
            throw ShuoError.recordingFailed
        }
    }

    public func previewURL() async throws -> URL {
        guard state == .paused else { throw ShuoError.recordingFailed }
        guard !segmentURLs.isEmpty else { throw ShuoError.recordingFailed }

        if segmentURLs.count == 1, let only = segmentURLs.first { return only }
        if let previewFileURL, previewSegmentCount == segmentURLs.count { return previewFileURL }

        let merged = try Self.makeRecordingURL()
        do {
            try await AudioSegmentMerger.merge(segmentURLs, into: merged)
        } catch {
            try? FileManager.default.removeItem(at: merged)
            throw ShuoError.recordingFailed
        }

        if let stale = previewFileURL { try? FileManager.default.removeItem(at: stale) }
        previewFileURL = merged
        previewSegmentCount = segmentURLs.count
        return merged
    }

    public func finish() async throws -> AudioRecording {
        guard state == .recording || state == .paused else { throw ShuoError.recordingFailed }

        engine.stop()
        state = .ended
        sealCurrentSegment()

        let liveTranscript = await transcription.finish()
        let duration = currentDuration
        let samples = waveformSamples
        guard duration > 0, !segmentURLs.isEmpty else {
            await tearDown(deletingFiles: true)
            throw ShuoError.recordingFailed
        }

        let url: URL
        do {
            url = try await consolidatedRecordingURL()
        } catch {
            await tearDown(deletingFiles: true)
            throw ShuoError.recordingFailed
        }

        // Keeps `url`; `consolidatedRecordingURL()` has already removed anything it
        // superseded.
        await tearDown(deletingFiles: false)

        return AudioRecording(
            fileURL: url,
            duration: duration,
            waveformSamples: samples,
            liveTranscript: liveTranscript
        )
    }

    public func discard() async {
        guard state != .ended else { return }
        engine.stop()
        state = .ended
        await transcription.cancel()
        await tearDown(deletingFiles: true)
    }

    // MARK: - Segments

    /// Opens the next segment for writing.
    private func openSegment() throws {
        guard let recordingFormat else { throw ShuoError.recordingFailed }
        let url = try Self.makeRecordingURL()
        file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: recordingFormat.sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
        )
        fileURL = url
    }

    /// Closes the open segment, if there is one, and records it as complete.
    ///
    /// Releasing the `AVAudioFile` is what writes the AAC index and makes the file
    /// readable — there is no explicit close on the API, which is why this reads as an
    /// assignment doing more than an assignment.
    private func sealCurrentSegment() {
        file = nil
        if let fileURL { segmentURLs.append(fileURL) }
        fileURL = nil
    }

    /// The whole take as one file, merging only when it was actually captured in pieces.
    ///
    /// Adopts an up-to-date `previewURL()` result rather than exporting the same audio
    /// twice — the ordinary path here is a user who paused, replayed their take, and then
    /// confirmed it.
    private func consolidatedRecordingURL() async throws -> URL {
        if segmentURLs.count == 1, let only = segmentURLs.first { return only }

        if let previewFileURL, previewSegmentCount == segmentURLs.count {
            for segment in segmentURLs { try? FileManager.default.removeItem(at: segment) }
            segmentURLs = [previewFileURL]
            self.previewFileURL = nil
            return previewFileURL
        }

        let merged = try Self.makeRecordingURL()
        try await AudioSegmentMerger.merge(segmentURLs, into: merged)
        for segment in segmentURLs { try? FileManager.default.removeItem(at: segment) }
        segmentURLs = [merged]
        return merged
    }

    // MARK: - Capture pipeline

    private func process(_ samples: [Float]) async {
        guard state == .recording, let recordingFormat, let file else { return }
        guard let buffer = Self.makeBuffer(from: samples, format: recordingFormat) else { return }

        do {
            try file.write(from: buffer)
        } catch {
            eventContinuation.yield(.failed(.recordingFailed))
            return
        }

        framesWritten += AVAudioFramePosition(samples.count)

        // One bar per tick: at ~12Hz the waveform advances at a readable pace.
        let amplitudes = WaveformSampler.amplitudes(from: samples, binCount: 1)
        waveformSamples.append(contentsOf: amplitudes)
        eventContinuation.yield(.tick(amplitudes: amplitudes, duration: currentDuration))

        await transcription.append(buffer)
    }

    /// Derived from frames actually written, so it cannot drift from the audio on disk
    /// and needs no special handling across pause/resume.
    private var currentDuration: TimeInterval {
        guard let recordingFormat, recordingFormat.sampleRate > 0 else { return 0 }
        return Double(framesWritten) / recordingFormat.sampleRate
    }

    // MARK: - Interruptions

    // An incoming call or an unplugged headset stops the engine underneath us. Without
    // this the UI would sit in `.recording` capturing silence.
    //
    // The observer tokens are held on the actor rather than captured by the stream's
    // termination handler: they are not `Sendable`, and keeping them isolated here means
    // teardown can remove them without an unsafe opt-out.
    private func observeDisruptions() {
        guard observerTokens.isEmpty else { return }

        let center = NotificationCenter.default
        let (disruptions, continuation) = AsyncStream.makeStream(of: Void.self)

        observerTokens = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began
                else { return }
                continuation.yield()
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
                else { return }
                continuation.yield()
            },
        ]

        disruptionTask = Task { [weak self] in
            for await _ in disruptions {
                await self?.handleDisruption()
            }
        }
    }

    private func handleDisruption() {
        guard state == .recording else { return }
        engine.pause()
        state = .paused
        eventContinuation.yield(.interrupted)
    }

    private func removeDisruptionObservers() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens = []
    }

    // MARK: - Teardown

    private func tearDown(deletingFiles: Bool) async {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)

        processingTask?.cancel()
        processingTask = nil
        disruptionTask?.cancel()
        disruptionTask = nil
        removeDisruptionObservers()

        file = nil

        // Always: a preview is a throwaway copy for the replay control, never the take
        // itself. `consolidatedRecordingURL()` clears this first when it adopts one.
        if let previewFileURL {
            try? FileManager.default.removeItem(at: previewFileURL)
            self.previewFileURL = nil
            previewSegmentCount = 0
        }

        if deletingFiles {
            for segment in segmentURLs { try? FileManager.default.removeItem(at: segment) }
            segmentURLs = []
            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
                self.fileURL = nil
            }
        }

        eventContinuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Mode must stay `.default` here. `.spokenAudio` is a *playback* mode (podcasts,
        // audiobooks) and is not valid with `.record` — pairing them throws BadParam on a
        // real device, though the Simulator accepts it silently, so this fails only on
        // hardware. `.measurement` is the other tempting choice, but it disables the input
        // processing that helps transcription in a noisy room, and the waveform does not
        // need that precision.
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
    }

    private static func makeRecordingURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
    }

    private static func makeBuffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
