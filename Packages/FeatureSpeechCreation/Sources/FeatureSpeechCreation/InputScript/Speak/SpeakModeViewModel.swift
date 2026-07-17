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

    // MARK: DEBUG_LIVE_TRANSCRIPT — temporary; delete this property, the `.transcript`
    // case in `handle(_:)`, and the panel in SpeakModeView. The shipped design never
    // shows the live transcript: it arrives once, on `AudioRecording.liveTranscript`.
    public private(set) var debugLiveTranscript = ""
    // MARK: END DEBUG_LIVE_TRANSCRIPT

    private let capturer: any AudioCapturing
    private let permissions: any MicrophonePermissionProviding
    private var eventTask: Task<Void, Never>?

    public init(capturer: any AudioCapturing, permissions: any MicrophonePermissionProviding) {
        self.capturer = capturer
        self.permissions = permissions

        let events = capturer.events
        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
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

    public var isRecording: Bool {
        viewState == .recording
    }

    /// "mm.ss,cs" — matches the design's `00.05,40`.
    public var formattedDuration: String {
        let totalCentiseconds = Int((max(0, duration) * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d.%02d,%02d", minutes, seconds, centiseconds)
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

    /// Abandons the session and deletes the captured audio.
    ///
    /// The teardown is tracked on `transitionTask` rather than fired and forgotten, so
    /// callers (and tests) can await the capturer actually releasing the microphone
    /// instead of guessing when it happened.
    public func cancel() {
        transitionTask?.cancel()
        eventTask?.cancel()
        eventTask = nil

        // Held locally so the task does not keep this view model alive just to tear down.
        let capturer = self.capturer
        transitionTask = Task { await capturer.discard() }
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
        debugLiveTranscript = "" // DEBUG_LIVE_TRANSCRIPT
    }

    // MARK: - Events

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
        default:
            "Something went wrong while recording. Please try again."
        }
    }
}
