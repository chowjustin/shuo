//
//  PreviewDoubles.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 17/07/26.
//

// Preview-only scaffolding: stand-ins for the services this package's view models expect,
// so `#Preview` can build a view model without the app's composition root.
//
// These are not test doubles — the real ones live in ShuoTestSupport (CLAUDE.md §7), which
// this package's *runtime* target deliberately does not depend on, since that would ship
// fakes inside the app. `#if DEBUG` keeps them out of release builds regardless.
//
// Exempt from the one-type-per-file rule (CLAUDE.md §5) on the grounds that none of it is
// load-bearing: deleting this file breaks previews and nothing else.

#if DEBUG
import Foundation
import ShuoCore

extension InputScriptViewModel {
    static func preview(
        purpose: SpeechPurpose = .persuade,
        permissionStatus: MicrophonePermissionStatus = .granted,
        initialText: String? = nil
    ) -> InputScriptViewModel {
        InputScriptViewModel(
            purpose: purpose,
            fileImporter: PreviewFileImporting(),
            audioCapturer: PreviewAudioCapturing(),
            microphonePermissions: PreviewMicrophonePermissionProviding(status: permissionStatus),
            generateTranscript: GenerateTranscriptUseCase(transcriber: PreviewSpeechTranscribing()),
            initialText: initialText
        )
    }
}

extension SpeakModeViewModel {
    static func preview(
        permissionStatus: MicrophonePermissionStatus = .granted
    ) -> SpeakModeViewModel {
        SpeakModeViewModel(
            capturer: PreviewAudioCapturing(),
            permissions: PreviewMicrophonePermissionProviding(status: permissionStatus)
        )
    }
}

struct PreviewFileImporting: FileImporting {
    func importFile(from url: URL) async throws -> ImportedMedia {
        ImportedMedia(
            fileURL: url,
            kind: .audio,
            originalFileName: url.lastPathComponent,
            duration: 83.7
        )
    }
}

/// Pauses before returning, so previews show the loading screen rather than snapping
/// straight to the finished transcript.
struct PreviewSpeechTranscribing: SpeechTranscribing {
    var delay: Duration = .seconds(2)
    var result: Result<String, ShuoError> = .success(
        "Joining a campus organization is the fastest way to find people who care about "
        + "the same things you do, and the skills you build there follow you long after "
        + "you graduate."
    )

    func transcribe(_ input: TranscriptionInput) async throws -> String {
        try? await Task.sleep(for: delay)
        return try result.get()
    }
}

struct PreviewMicrophonePermissionProviding: MicrophonePermissionProviding {
    let status: MicrophonePermissionStatus

    func currentStatus() async -> MicrophonePermissionStatus { status }
    func request() async -> MicrophonePermissionStatus { status }
}

/// Emits synthetic ticks on a timer, so previews show a moving waveform and a running
/// clock instead of a frozen one.
actor PreviewAudioCapturing: AudioCapturing {
    nonisolated let events: AsyncStream<AudioCaptureEvent>
    private let continuation: AsyncStream<AudioCaptureEvent>.Continuation
    private var tickTask: Task<Void, Never>?
    private var elapsed: TimeInterval = 0

    private static let tickInterval: Duration = .milliseconds(80)
    private static let tickSeconds: TimeInterval = 0.08

    init() {
        let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
        self.events = events
        self.continuation = continuation
    }

    func prepare() async {}

    func start() async throws {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: PreviewAudioCapturing.tickInterval)
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    func pause() async throws { tickTask?.cancel() }

    func resume() async throws { try await start() }

    func finish() async throws -> AudioRecording {
        tickTask?.cancel()
        let recording = AudioRecording(
            fileURL: URL(filePath: "/tmp/preview.m4a"),
            duration: elapsed,
            liveTranscript: "Why we must join campus organizations."
        )
        continuation.finish()
        return recording
    }

    func discard() async {
        tickTask?.cancel()
        continuation.finish()
    }

    private func tick() {
        elapsed += Self.tickSeconds
        continuation.yield(.tick(amplitudes: [Float.random(in: 0.1...1)], duration: elapsed))
        continuation.yield(.transcript("Why we must join campus organizations")) // DEBUG_LIVE_TRANSCRIPT
    }
}
#endif
