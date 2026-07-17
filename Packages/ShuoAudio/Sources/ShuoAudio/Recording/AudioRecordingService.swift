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
    private var file: AVAudioFile?
    private var fileURL: URL?
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

            let url = try Self.makeRecordingURL()
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: recordingFormat.sampleRate,
                    AVNumberOfChannelsKey: 1,
                ]
            )

            self.file = file
            self.fileURL = url
            self.recordingFormat = recordingFormat

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
            await tearDown(deletingFile: true)
            throw error
        } catch {
            // The one place the real AVFoundation error exists before it is flattened.
            Self.log.error("Recording could not start: \(error.localizedDescription, privacy: .public) — \(String(describing: error), privacy: .public)")
            await tearDown(deletingFile: true)
            throw ShuoError.recordingFailed
        }
    }

    public func pause() async throws {
        guard state == .recording else { return }
        engine.pause()
        state = .paused
    }

    public func resume() async throws {
        guard state == .paused else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            state = .recording
        } catch {
            throw ShuoError.recordingFailed
        }
    }

    public func finish() async throws -> AudioRecording {
        guard state == .recording || state == .paused else { throw ShuoError.recordingFailed }

        engine.stop()
        state = .ended

        let liveTranscript = await transcription.finish()
        let duration = currentDuration
        let samples = waveformSamples
        guard let url = fileURL, duration > 0 else {
            await tearDown(deletingFile: true)
            throw ShuoError.recordingFailed
        }

        await tearDown(deletingFile: false)

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
        await tearDown(deletingFile: true)
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

    private func tearDown(deletingFile: Bool) async {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)

        processingTask?.cancel()
        processingTask = nil
        disruptionTask?.cancel()
        disruptionTask = nil
        removeDisruptionObservers()

        file = nil
        if deletingFile, let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
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
