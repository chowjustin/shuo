//
//  SpeakModeViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Idle→recording→paused→recording→finished state machine,
// driven through `AudioCapturing` (ShuoCore) injected via the initializer — never a
// concrete `ShuoAudio` type (CLAUDE.md §4). See ARCHITECTURE.md §3.1.3.

import Foundation
import Observation
import ShuoCore

@Observable
@MainActor
public final class SpeakModeViewModel {

    /// How many bars the waveform shows. The window is pre-filled with silence so the
    /// waveform spans its full width from the first frame rather than growing into it.
    static let waveformWindowSize = 25

    public private(set) var viewState: SpeakModeViewState = .idle
    /// The rolling waveform window — oldest first, always `waveformWindowSize` long once
    /// recording has started, and empty while idle.
    public private(set) var displaySamples: [Float] = []
    public private(set) var duration: TimeInterval = 0

    /// The in-flight state transition, exposed so tests can await it rather than sleep.
    public private(set) var transitionTask: Task<Void, Never>?

    // MARK: - Playback

    /// True while the captured take is playing back.
    public private(set) var isPlayingBack = false
    /// How far into the take playback has reached, in seconds.
    public private(set) var playbackPosition: TimeInterval = 0
    /// Why replay failed, if it did. Never blocks the flow — a take that cannot be played
    /// is still perfectly transcribable — so it is shown beside the control, not instead
    /// of the screen.
    public private(set) var playbackError: String?
    /// The in-flight playback transition, exposed so tests can await it.
    public private(set) var playbackTask: Task<Void, Never>?

    // MARK: DEBUG_LIVE_TRANSCRIPT — temporary; delete this property, the `.transcript`
    // case in `handle(_:)`, and the panel in SpeakModeView. The shipped design never
    // shows the live transcript: it arrives once, on `AudioRecording.liveTranscript`.
    public private(set) var debugLiveTranscript = ""
    // MARK: END DEBUG_LIVE_TRANSCRIPT

    /// Builds a capture session.
    ///
    /// A factory rather than one injected instance because `AudioCapturing` is single-use
    /// by contract — its event stream completes when the session ends — and Retake has to
    /// be able to start over. Handing this view model a used capturer would give the
    /// second take a dead stream.
    private let makeCapturer: @Sendable () -> any AudioCapturing
    private var capturer: any AudioCapturing
    private let permissions: any MicrophonePermissionProviding
    private let player: any AudioPlaying
    private let recordingDeleter: any AudioRecordingDeleting
    private var eventTask: Task<Void, Never>?
    private var playbackEventTask: Task<Void, Never>?

    public init(
        makeCapturer: @escaping @Sendable () -> any AudioCapturing,
        permissions: any MicrophonePermissionProviding,
        player: any AudioPlaying,
        recordingDeleter: any AudioRecordingDeleting
    ) {
        self.makeCapturer = makeCapturer
        self.capturer = makeCapturer()
        self.permissions = permissions
        self.player = player
        self.recordingDeleter = recordingDeleter

        observeCapturer()
        observePlayer()
    }

    // MARK: - Derived state

    public var recording: AudioRecording? {
        if case .finished(let recording) = viewState { return recording }
        return nil
    }

    /// The captured audio as a domain `SpeechSource`, once there is one.
    public var speechSource: SpeechSource? {
        recording.map(SpeechSource.recordedAudio)
    }

    /// Whether the user can move on. True only once paused with audio captured — mid
    /// recording there is nothing to confirm yet.
    public var canProceed: Bool {
        switch viewState {
        case .paused: duration > 0
        case .finished: true
        default: false
        }
    }

    /// Whether there is a take to hear back.
    ///
    /// Deliberately the same condition as `canProceed`: anything the user is allowed to
    /// send forward, they are allowed to listen to first.
    public var canReplay: Bool {
        canProceed
    }

    /// Whether the take can still be added to.
    ///
    /// False once `finish()` has run — the session is over, and the only ways on from
    /// there are to proceed or to retake. This is what a user sees after stepping back
    /// from the analysis screen.
    public var canResumeRecording: Bool {
        viewState == .paused
    }

    /// Whether there is a take worth offering to throw away.
    public var canRetake: Bool {
        switch viewState {
        case .paused, .finished, .failed: true
        case .recording: duration > 0
        case .idle, .requestingPermission, .permissionDenied: false
        }
    }

    public var isRecording: Bool {
        viewState == .recording
    }

    /// How far through the take playback has reached, 0...1, for the waveform playhead.
    public var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(playbackPosition / duration, 0), 1)
    }

    /// "mm.ss,cs" — matches the design's `00.05,40`.
    public var formattedDuration: String {
        Self.formatted(duration)
    }

    /// The take's length, or the playhead while it is playing — the same label, showing
    /// whichever number is currently the live one.
    public var formattedTimeLabel: String {
        isPlayingBack ? Self.formatted(playbackPosition) : formattedDuration
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let totalCentiseconds = Int((max(0, seconds) * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secondsPart = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d.%02d,%02d", minutes, secondsPart, centiseconds)
    }

    // MARK: - Intents

    /// Best-effort warm-up. Safe to call repeatedly.
    public func prepare() async {
        guard viewState == .idle else { return }
        await capturer.prepare()
    }

    /// The single microphone/pause/resume button.
    public func primaryAction() {
        switch viewState {
        case .idle: startRecording()
        case .recording: pauseRecording()
        case .paused: resumeRecording()
        case .requestingPermission, .permissionDenied, .finished, .failed: break
        }
    }

    /// Ends the session and returns what was captured, for the caller to hand to the
    /// next step. Returns nil if there was nothing to finish.
    public func finish() async -> AudioRecording? {
        stopPlayback()
        if case .finished(let recording) = viewState { return recording }
        guard canProceed else { return nil }

        transitionTask?.cancel()
        do {
            let recording = try await capturer.finish()
            viewState = .finished(recording)
            return recording
        } catch {
            viewState = .failed(Self.message(for: error))
            return nil
        }
    }

    /// Throws the current take away and returns to an empty recorder, ready to start over.
    ///
    /// Deliberately not guarded by a confirmation, to match Attach File's "Reupload File"
    /// — the two are the same gesture in two modes, and the segmented control puts them
    /// one tap apart.
    ///
    /// The audio file is deleted here rather than left behind: `AudioCapturing.discard()`
    /// cannot reach a take whose session already ended (the ✓ → back path), so the take is
    /// deleted explicitly through `AudioRecordingDeleting` as well.
    public func retake() {
        let outgoingCapturer = capturer
        let discarded = recording

        transitionTask?.cancel()
        eventTask?.cancel()
        playbackTask?.cancel()
        isPlayingBack = false
        playbackPosition = 0

        capturer = makeCapturer()
        observeCapturer()
        reset()

        let incomingCapturer = capturer
        transitionTask = Task { [player, recordingDeleter] in
            await player.stop()
            await outgoingCapturer.discard()
            if let discarded { await recordingDeleter.delete(discarded) }
            await incomingCapturer.prepare()
        }
    }

    /// Starts, or suspends, hearing the take back.
    public func togglePlayback() {
        if isPlayingBack {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    /// Abandons the session and deletes the captured audio.
    ///
    /// The teardown is tracked on `transitionTask` rather than fired and forgotten, so
    /// callers (and tests) can await the capturer actually releasing the microphone
    /// instead of guessing when it happened.
    public func cancel() {
        let outgoingCapturer = capturer
        let discarded = recording

        transitionTask?.cancel()
        eventTask?.cancel()
        eventTask = nil
        playbackTask?.cancel()
        playbackTask = nil
        playbackEventTask?.cancel()
        playbackEventTask = nil

        transitionTask = Task { [player, recordingDeleter] in
            await player.stop()
            await outgoingCapturer.discard()
            // `discard()` is a no-op once the session has ended, so a take that was
            // finished — and then carried through transcription and back — is only
            // actually removed by this.
            if let discarded { await recordingDeleter.delete(discarded) }
        }
        reset()
    }

    // MARK: - Transitions

    private func startRecording() {
        // Cancel-and-replace rather than queue: a double tap must not start two sessions
        // (CLAUDE.md §6).
        transitionTask?.cancel()
        viewState = .requestingPermission
        transitionTask = Task { [weak self] in
            guard let self else { return }
            let status = await permissions.request()
            guard !Task.isCancelled else { return }

            guard status == .granted else {
                viewState = .permissionDenied
                return
            }

            do {
                try await capturer.start()
                guard !Task.isCancelled else { return }
                duration = 0
                displaySamples = Array(repeating: 0, count: Self.waveformWindowSize)
                viewState = .recording
            } catch {
                guard !Task.isCancelled else { return }
                viewState = .failed(Self.message(for: error))
            }
        }
    }

    private func pauseRecording() {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            // Flip first: the button must respond immediately, and a failed pause is
            // reported by the capturer through `events` regardless.
            viewState = .paused
            try? await capturer.pause()
        }
    }

    private func resumeRecording() {
        // Recording over the top of playback would capture the take being played back.
        stopPlayback()
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capturer.resume()
                guard !Task.isCancelled else { return }
                viewState = .recording
            } catch {
                guard !Task.isCancelled else { return }
                viewState = .failed(Self.message(for: error))
            }
        }
    }

    private func reset() {
        viewState = .idle
        displaySamples = []
        duration = 0
        isPlayingBack = false
        playbackPosition = 0
        playbackError = nil
        debugLiveTranscript = "" // DEBUG_LIVE_TRANSCRIPT
    }

    // MARK: - Playback

    private func startPlayback() {
        guard canReplay else { return }
        playbackTask?.cancel()
        playbackError = nil

        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await playbackURL()
                guard !Task.isCancelled else { return }
                try await player.play(url: url)
                guard !Task.isCancelled else { return }
                isPlayingBack = true
            } catch {
                guard !Task.isCancelled else { return }
                isPlayingBack = false
                playbackError = Self.playbackFailureMessage
            }
        }
    }

    /// Where the audio to play lives.
    ///
    /// A finished take is a file of its own; a paused one is still mid-session, so the
    /// capturer has to assemble a playable copy first (`AudioCapturing.previewURL()`).
    private func playbackURL() async throws -> URL {
        if case .finished(let recording) = viewState { return recording.fileURL }
        return try await capturer.previewURL()
    }

    private func pausePlayback() {
        playbackTask?.cancel()
        isPlayingBack = false
        playbackTask = Task { [player] in await player.pause() }
    }

    /// Ends playback and rewinds, for the paths that take the take away — retaking,
    /// resuming, confirming, leaving.
    private func stopPlayback() {
        guard isPlayingBack || playbackPosition > 0 else { return }
        playbackTask?.cancel()
        isPlayingBack = false
        playbackPosition = 0
        playbackTask = Task { [player] in await player.stop() }
    }

    private func observePlayer() {
        let events = player.events
        playbackEventTask = Task { [weak self] in
            for await event in events {
                self?.handle(playback: event)
            }
        }
    }

    /// Applies one playback event. Synchronous and separate from the stream feeding it,
    /// for the same reason as `handle(_ event: AudioCaptureEvent)` below.
    ///
    /// Labelled rather than overloaded: both event enums carry a `.failed` case, so
    /// `handle(.failed(...))` would be ambiguous at every call site.
    func handle(playback event: AudioPlaybackEvent) {
        switch event {
        case .progress(let position):
            guard isPlayingBack else { return }
            playbackPosition = position

        case .finished:
            isPlayingBack = false
            playbackPosition = 0

        case .failed:
            isPlayingBack = false
            playbackPosition = 0
            playbackError = Self.playbackFailureMessage
        }
    }

    // MARK: - Events

    private func observeCapturer() {
        let events = capturer.events
        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    /// Applies one capture event.
    ///
    /// Deliberately synchronous and separate from the stream that feeds it: all the
    /// logic worth testing lives here, and tests can drive it directly instead of racing
    /// an `AsyncStream`.
    func handle(_ event: AudioCaptureEvent) {
        switch event {
        case .tick(let amplitudes, let duration):
            // A tick that arrives after the user paused would rewind the timer.
            guard viewState == .recording else { return }
            self.duration = duration
            displaySamples = Self.window(appending: amplitudes, to: displaySamples)

        case .interrupted:
            guard viewState == .recording else { return }
            viewState = .paused

        case .failed(let error):
            viewState = .failed(Self.message(for: error))

        // MARK: DEBUG_LIVE_TRANSCRIPT — temporary; delete this case.
        case .transcript(let text):
            debugLiveTranscript = text
        // MARK: END DEBUG_LIVE_TRANSCRIPT
        }
    }

    /// Appends new samples and trims the oldest, keeping the window a fixed width.
    static func window(appending new: [Float], to current: [Float]) -> [Float] {
        guard waveformWindowSize > 0 else { return [] }
        var combined = current + new
        if combined.count > waveformWindowSize {
            combined.removeFirst(combined.count - waveformWindowSize)
        }
        return combined
    }

    private static func message(for error: any Error) -> String {
        guard let error = error as? ShuoError else {
            return "Something went wrong while recording. Please try again."
        }
        return switch error {
        case .microphonePermissionDenied:
            "Shuo needs microphone access to record your ideas."
        case .audioNotDetected:
            "We couldn't detect any audio. Try speaking closer to the mic."
        case .storageFull:
            "Your device storage is full. Free up some space and try again."
        default:
            "Something went wrong while recording. Please try again."
        }
    }

    /// One message for every replay failure. There is nothing the user can do
    /// differently, and the take is still usable, so distinguishing the causes would only
    /// give them more to read.
    static let playbackFailureMessage =
        "Couldn't play this recording back. You can still continue with it."
}
