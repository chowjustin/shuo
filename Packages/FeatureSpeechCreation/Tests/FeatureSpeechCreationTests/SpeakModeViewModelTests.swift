//
//  SpeakModeViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

// `@MainActor` Swift Testing suite for `SpeakModeViewModel`'s recording state machine,
// injecting `FakeAudioCapturing` from ShuoTestSupport.

import Foundation
import Synchronization
import Testing
import ShuoCore
import ShuoTestSupport
@testable import FeatureSpeechCreation

/// Vends capture sessions in order, so a test can hold on to both the session a take was
/// recorded in *and* the one Retake replaces it with. Mirrors the real composition root,
/// which hands over a factory rather than an instance because `AudioCapturing` is
/// single-use.
private final class CapturerSequence: Sendable {
    private let capturers: [FakeAudioCapturing]
    private let position = Mutex(0)

    init(_ capturers: [FakeAudioCapturing]) {
        self.capturers = capturers
    }

    func next() -> any AudioCapturing {
        let index = position.withLock { value -> Int in
            defer { value += 1 }
            return value
        }
        guard index < capturers.count else { return FakeAudioCapturing() }
        return capturers[index]
    }
}

@MainActor
@Suite("SpeakModeViewModel")
struct SpeakModeViewModelTests {

    private func makeViewModel(
        capturer: FakeAudioCapturing = FakeAudioCapturing(),
        nextCapturer: FakeAudioCapturing = FakeAudioCapturing(),
        player: FakeAudioPlaying = FakeAudioPlaying(),
        deleter: FakeAudioRecordingDeleting = FakeAudioRecordingDeleting(),
        permissionStatus: MicrophonePermissionStatus = .granted
    ) -> SpeakModeViewModel {
        let sequence = CapturerSequence([capturer, nextCapturer])
        return SpeakModeViewModel(
            makeCapturer: { sequence.next() },
            permissions: FakeMicrophonePermissionProviding(status: permissionStatus),
            player: player,
            recordingDeleter: deleter
        )
    }

    /// Drives the view model to a finished take — the state a user is in after confirming
    /// and stepping back from a later screen.
    private func makeFinishedViewModel(
        capturer: FakeAudioCapturing = FakeAudioCapturing(),
        nextCapturer: FakeAudioCapturing = FakeAudioCapturing(),
        player: FakeAudioPlaying = FakeAudioPlaying(),
        deleter: FakeAudioRecordingDeleting = FakeAudioRecordingDeleting()
    ) async -> SpeakModeViewModel {
        let viewModel = makeViewModel(
            capturer: capturer,
            nextCapturer: nextCapturer,
            player: player,
            deleter: deleter
        )
        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        _ = await viewModel.finish()
        return viewModel
    }

    /// Drives the view model to `.recording`, the entry point for most of these tests.
    private func makeRecordingViewModel(
        capturer: FakeAudioCapturing = FakeAudioCapturing()
    ) async -> SpeakModeViewModel {
        let viewModel = makeViewModel(capturer: capturer)
        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        return viewModel
    }

    // MARK: - Idle

    @Test("starts idle with no waveform and no duration")
    func startsIdle() {
        let viewModel = makeViewModel()

        #expect(viewModel.viewState == .idle)
        #expect(viewModel.displaySamples.isEmpty)
        #expect(viewModel.duration == 0)
        #expect(viewModel.recording == nil)
        #expect(viewModel.speechSource == nil)
        #expect(!viewModel.canProceed)
    }

    // MARK: - Permission

    @Test("starts recording once microphone permission is granted")
    func startsRecordingWhenPermissionGranted() async {
        let capturer = FakeAudioCapturing()
        let viewModel = await makeRecordingViewModel(capturer: capturer)

        #expect(viewModel.viewState == .recording)
        #expect(await capturer.startCount == 1)
    }

    @Test("does not start recording when microphone permission is denied")
    func doesNotStartRecordingWhenPermissionDenied() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer, permissionStatus: .denied)

        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        #expect(viewModel.viewState == .permissionDenied)
        #expect(await capturer.startCount == 0)
    }

    @Test("the microphone button does nothing once permission has been denied")
    func primaryActionIsInertAfterPermissionDenied() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer, permissionStatus: .denied)

        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        #expect(viewModel.viewState == .permissionDenied)
        #expect(await capturer.startCount == 0)
    }

    // MARK: - State machine

    @Test("runs idle to recording to paused to recording to finished")
    func runsTheFullStateMachine() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)

        #expect(viewModel.viewState == .idle)

        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        #expect(viewModel.viewState == .recording)

        viewModel.handle(.tick(amplitudes: [0.5], duration: 1))

        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        #expect(viewModel.viewState == .paused)

        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        #expect(viewModel.viewState == .recording)

        viewModel.handle(.tick(amplitudes: [0.5], duration: 2))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        let recording = await viewModel.finish()

        #expect(recording != nil)
        #expect(viewModel.viewState == .finished(FakeAudioCapturing.defaultRecording))
        #expect(await capturer.startCount == 1)
        #expect(await capturer.pauseCount == 2)
        #expect(await capturer.resumeCount == 1)
        #expect(await capturer.finishCount == 1)
    }

    @Test("reports a failure when capture cannot start")
    func reportsFailureWhenStartFails() async {
        let capturer = FakeAudioCapturing(startError: .recordingFailed)
        let viewModel = makeViewModel(capturer: capturer)

        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        guard case .failed = viewModel.viewState else {
            Issue.record("Expected failed, got \(viewModel.viewState)")
            return
        }
        #expect(!viewModel.canProceed)
    }

    @Test("a double tap starts only one recording session")
    func doubleTapStartsOneSession() async {
        // Cancel-and-replace, not queue: two sessions would leave one capturing
        // unreachable audio (CLAUDE.md §6).
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)

        viewModel.primaryAction()
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        #expect(viewModel.viewState == .recording)
        #expect(await capturer.startCount == 1)
    }

    // MARK: - canProceed

    @Test("cannot proceed while still recording")
    func cannotProceedWhileRecording() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))

        #expect(!viewModel.canProceed)
    }

    @Test("can proceed once paused with audio captured")
    func canProceedWhenPausedWithAudio() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))

        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        #expect(viewModel.canProceed)
    }

    @Test("cannot proceed when paused without any audio captured")
    func cannotProceedWhenPausedWithoutAudio() async {
        let viewModel = await makeRecordingViewModel()

        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        #expect(viewModel.viewState == .paused)
        #expect(viewModel.duration == 0)
        #expect(!viewModel.canProceed)
    }

    // MARK: - finish

    @Test("finish does nothing when there is nothing to finish")
    func finishIsInertWhenIdle() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)

        let recording = await viewModel.finish()

        #expect(recording == nil)
        #expect(viewModel.viewState == .idle)
        #expect(await capturer.finishCount == 0)
    }

    @Test("finish is idempotent and does not end the session twice")
    func finishIsIdempotent() async {
        let capturer = FakeAudioCapturing()
        let viewModel = await makeRecordingViewModel(capturer: capturer)
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        let first = await viewModel.finish()
        let second = await viewModel.finish()

        #expect(first?.id == second?.id)
        #expect(await capturer.finishCount == 1)
    }

    @Test("reports a failure when the session cannot be finished")
    func reportsFailureWhenFinishFails() async {
        let capturer = FakeAudioCapturing(finishError: .recordingFailed)
        let viewModel = await makeRecordingViewModel(capturer: capturer)
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        let recording = await viewModel.finish()

        #expect(recording == nil)
        guard case .failed = viewModel.viewState else {
            Issue.record("Expected failed, got \(viewModel.viewState)")
            return
        }
    }

    @Test("exposes the finished recording as a speech source")
    func exposesFinishedRecordingAsSpeechSource() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        _ = await viewModel.finish()

        #expect(viewModel.speechSource == .recordedAudio(FakeAudioCapturing.defaultRecording))
    }

    @Test("carries the live transcript through to the finished recording")
    func carriesLiveTranscriptThrough() async {
        // The whole point of transcribing during capture: the next step should not have
        // to transcribe the file again.
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        let recording = await viewModel.finish()

        #expect(recording?.liveTranscript == "Why we must join campus organizations.")
    }

    // MARK: - cancel

    @Test("cancel discards the session and returns to idle")
    func cancelReturnsToIdle() async {
        let capturer = FakeAudioCapturing()
        let viewModel = await makeRecordingViewModel(capturer: capturer)
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))

        viewModel.cancel()

        #expect(viewModel.viewState == .idle)
        #expect(viewModel.displaySamples.isEmpty)
        #expect(viewModel.duration == 0)
    }

    // MARK: - Ticks

    @Test("a tick updates the duration and the waveform")
    func tickUpdatesDurationAndWaveform() async {
        let viewModel = await makeRecordingViewModel()

        viewModel.handle(.tick(amplitudes: [0.9], duration: 1.5))

        #expect(viewModel.duration == 1.5)
        #expect(viewModel.displaySamples.last == 0.9)
    }

    @Test("the waveform spans its full width from the first frame")
    func waveformIsFullWidthImmediately() async {
        // Pre-filled with silence, so a session that has started but captured no sound
        // reads as a full-width dashed line rather than growing in from the left.
        let viewModel = await makeRecordingViewModel()

        #expect(viewModel.displaySamples.count == SpeakModeViewModel.waveformWindowSize)
        #expect(viewModel.displaySamples.allSatisfy { $0 == 0 })
    }

    @Test("the waveform holds a fixed window, dropping the oldest samples")
    func waveformHoldsFixedWindow() async {
        let viewModel = await makeRecordingViewModel()
        let size = SpeakModeViewModel.waveformWindowSize

        for index in 0..<(size * 2) {
            viewModel.handle(.tick(amplitudes: [Float(index) / Float(size * 2)], duration: 1))
        }

        #expect(viewModel.displaySamples.count == size)
        // The most recent sample survives; the pre-filled silence has been pushed out.
        #expect(viewModel.displaySamples.last == Float(size * 2 - 1) / Float(size * 2))
    }

    @Test("a tick arriving after pause does not rewind the timer")
    func tickAfterPauseIsIgnored() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 5))

        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.handle(.tick(amplitudes: [0.1], duration: 1))

        #expect(viewModel.duration == 5)
    }

    // MARK: - Interruption

    @Test("an interruption pauses recording")
    func interruptionPausesRecording() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))

        viewModel.handle(.interrupted)

        #expect(viewModel.viewState == .paused)
        // Audio captured before the call came in is still there to keep.
        #expect(viewModel.canProceed)
    }

    @Test("an interruption while already paused changes nothing")
    func interruptionWhilePausedIsIgnored() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        viewModel.handle(.interrupted)

        #expect(viewModel.viewState == .paused)
    }

    @Test("a capture failure surfaces as a failed state")
    func captureFailureSurfaces() async {
        let viewModel = await makeRecordingViewModel()

        viewModel.handle(.failed(.recordingFailed))

        guard case .failed = viewModel.viewState else {
            Issue.record("Expected failed, got \(viewModel.viewState)")
            return
        }
    }

    // MARK: - Stream wiring

    @Test("events emitted by the capturer reach the view model")
    func capturerEventsReachTheViewModel() async {
        // The rest of this suite drives `handle` directly for determinism; this covers
        // the one thing that cannot verify — that the stream is actually connected to it.
        let capturer = FakeAudioCapturing()
        let viewModel = await makeRecordingViewModel(capturer: capturer)

        capturer.emit(.tick(amplitudes: [0.7], duration: 4.2))

        await #expect(eventually { viewModel.duration == 4.2 })
    }

    // MARK: - Window

    @Test("the waveform window trims from the front, keeping newest samples")
    func windowTrimsFromTheFront() {
        let size = SpeakModeViewModel.waveformWindowSize
        let full = (0..<size).map { Float($0) }

        let result = SpeakModeViewModel.window(appending: [99, 100], to: full)

        #expect(result.count == size)
        #expect(result.first == 2)
        #expect(result.suffix(2) == [99, 100])
    }

    @Test("the waveform window trims a burst larger than the window itself")
    func windowTrimsOversizedBurst() {
        let size = SpeakModeViewModel.waveformWindowSize
        let burst = (0..<(size * 3)).map { Float($0) }

        let result = SpeakModeViewModel.window(appending: burst, to: [])

        #expect(result.count == size)
        #expect(result.last == Float(size * 3 - 1))
    }

    // MARK: - Duration formatting

    @Test(
        "formats the duration as mm.ss,cs",
        arguments: [
            (TimeInterval(0), "00.00,00"),
            (TimeInterval(5.4), "00.05,40"),
            (TimeInterval(6.4), "00.06,40"),
            (TimeInterval(59.99), "00.59,99"),
            (TimeInterval(60), "01.00,00"),
            (TimeInterval(125.07), "02.05,07"),
        ]
    )
    func formatsDuration(duration: TimeInterval, expected: String) async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0], duration: duration))

        #expect(viewModel.formattedDuration == expected)
    }

    @Test("formats a zero duration before anything is recorded")
    func formatsZeroDurationWhenIdle() {
        #expect(makeViewModel().formattedDuration == "00.00,00")
    }

    // MARK: - Retake

    @Test("retake throws the take away and returns to an empty recorder")
    func retakeReturnsToIdle() async {
        let viewModel = await makeRecordingViewModel()
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        viewModel.retake()
        await viewModel.transitionTask?.value

        #expect(viewModel.viewState == .idle)
        #expect(viewModel.duration == 0)
        #expect(viewModel.displaySamples.isEmpty)
        #expect(!viewModel.canProceed)
    }

    @Test("retake discards the session it replaces")
    func retakeDiscardsTheOldSession() async {
        let capturer = FakeAudioCapturing()
        let viewModel = await makeRecordingViewModel(capturer: capturer)
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))

        viewModel.retake()
        await viewModel.transitionTask?.value

        #expect(await capturer.discardCount == 1)
    }

    @Test("retake records into a new session, not the one that already ended")
    func retakeStartsAFreshSession() async {
        // `AudioCapturing` is single-use — its event stream completes when the session
        // ends — so reusing the finished one would leave the second take with a dead
        // stream and a waveform that never moves.
        let first = FakeAudioCapturing()
        let second = FakeAudioCapturing()
        let viewModel = await makeFinishedViewModel(capturer: first, nextCapturer: second)

        viewModel.retake()
        await viewModel.transitionTask?.value
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        #expect(viewModel.viewState == .recording)
        #expect(await second.startCount == 1)
        #expect(await first.startCount == 1)
    }

    @Test("retake deletes the audio behind a take whose session already ended")
    func retakeDeletesAFinishedTake() async {
        // `discard()` is a no-op once the session has ended, so this is the only thing
        // that actually removes the file a confirmed-then-abandoned take left on disk.
        let deleter = FakeAudioRecordingDeleting()
        let viewModel = await makeFinishedViewModel(deleter: deleter)

        viewModel.retake()
        await viewModel.transitionTask?.value

        #expect(await deleter.deleted == [FakeAudioCapturing.defaultRecording])
    }

    @Test("there is nothing to retake until something has been captured")
    func retakeIsOfferedOnlyOnceThereIsATake() async {
        let viewModel = makeViewModel()
        #expect(!viewModel.canRetake)

        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))

        #expect(viewModel.canRetake)
    }

    // MARK: - Replay

    @Test("a paused take plays the preview the capturer assembles, not a finished file")
    func pausedTakeReplaysThePreview() async {
        // Mid-session the audio is still being written, so the capturer has to close it
        // into a readable copy first — that copy is what plays.
        let capturer = FakeAudioCapturing()
        let player = FakeAudioPlaying()
        let viewModel = makeViewModel(capturer: capturer, player: player)
        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value

        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        #expect(await player.playedURLs == [FakeAudioCapturing.previewURL])
        #expect(viewModel.isPlayingBack)
    }

    @Test("a finished take plays its own file")
    func finishedTakeReplaysItsOwnFile() async {
        let player = FakeAudioPlaying()
        let viewModel = await makeFinishedViewModel(player: player)

        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        #expect(await player.playedURLs == [FakeAudioCapturing.defaultRecording.fileURL])
    }

    @Test("there is nothing to replay until there is a take")
    func replayIsOfferedOnlyOnceThereIsATake() async {
        let player = FakeAudioPlaying()
        let viewModel = makeViewModel(player: player)

        #expect(!viewModel.canReplay)
        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        #expect(await player.playedURLs.isEmpty)
        #expect(!viewModel.isPlayingBack)
    }

    @Test("toggling again pauses playback rather than restarting it")
    func togglingPausesPlayback() async {
        let player = FakeAudioPlaying()
        let viewModel = await makeFinishedViewModel(player: player)
        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        #expect(!viewModel.isPlayingBack)
        #expect(await player.pauseCount == 1)
        #expect(await player.playedURLs.count == 1)
    }

    @Test("the playhead advances while playing and rewinds when the take ends")
    func playheadTracksPlayback() async {
        let viewModel = await makeFinishedViewModel()
        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        viewModel.handle(playback: .progress(1.5))
        #expect(viewModel.playbackPosition == 1.5)
        #expect(viewModel.playbackProgress == 0.5)

        viewModel.handle(playback: .finished)
        #expect(!viewModel.isPlayingBack)
        #expect(viewModel.playbackPosition == 0)
    }

    @Test("progress arriving after playback stopped does not move the playhead")
    func lateProgressIsIgnored() async {
        // The player's ticker and the user's tap race by nature; a late tick must not
        // restart a playhead the user has already stopped.
        let viewModel = await makeFinishedViewModel()

        viewModel.handle(playback: .progress(2))

        #expect(viewModel.playbackPosition == 0)
    }

    @Test("a replay failure is reported without taking the take away")
    func replayFailureLeavesTheTakeUsable() async {
        let player = FakeAudioPlaying(playError: .playbackFailed)
        let viewModel = await makeFinishedViewModel(player: player)

        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        #expect(!viewModel.isPlayingBack)
        #expect(viewModel.playbackError == SpeakModeViewModel.playbackFailureMessage)
        // The whole point: a take that will not play is still a take.
        #expect(viewModel.canProceed)
        #expect(viewModel.speechSource != nil)
    }

    @Test("resuming a recording stops playback first")
    func resumingStopsPlayback() async {
        // Otherwise the microphone would capture the take being played back through it.
        let player = FakeAudioPlaying()
        let viewModel = makeViewModel(player: player)
        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.primaryAction()
        await viewModel.transitionTask?.value
        viewModel.togglePlayback()
        await viewModel.playbackTask?.value

        viewModel.primaryAction()
        await viewModel.playbackTask?.value
        await viewModel.transitionTask?.value

        #expect(!viewModel.isPlayingBack)
        #expect(await player.stopCount == 1)
        #expect(viewModel.viewState == .recording)
    }

    @Test("a finished take cannot be recorded into again")
    func finishedTakeCannotResume() async {
        // Its session is over; the ways on are proceeding or retaking, and offering a
        // resume control that could only fail would be worse than offering none.
        let viewModel = await makeFinishedViewModel()

        #expect(!viewModel.canResumeRecording)
        #expect(viewModel.canRetake)
        #expect(viewModel.canReplay)
    }

    // MARK: - cancel

    @Test("cancel deletes the audio behind a finished take")
    func cancelDeletesAFinishedTake() async {
        let deleter = FakeAudioRecordingDeleting()
        let player = FakeAudioPlaying()
        let viewModel = await makeFinishedViewModel(player: player, deleter: deleter)

        viewModel.cancel()
        await viewModel.transitionTask?.value

        #expect(await deleter.deleted == [FakeAudioCapturing.defaultRecording])
        #expect(await player.stopCount == 1)
    }

    // MARK: - Helpers

    /// Polls `condition` until it holds or the timeout elapses, so a test can wait on an
    /// `AsyncStream` delivery without sleeping for a fixed guess.
    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}
