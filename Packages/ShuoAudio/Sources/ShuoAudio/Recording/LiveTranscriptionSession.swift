//
//  LiveTranscriptionSession.swift
//  ShuoAudio
//
//  Created by Justin Chow on 17/07/26.
//

import AVFoundation
import Foundation
import Speech

/// Transcribes audio with `SpeechAnalyzer`/`SpeechTranscriber` while it is being
/// recorded, so the create flow does not have to transcribe the file afterwards.
///
/// **Every failure here is silent and non-fatal by design.** Live transcription is an
/// optimization layered on top of recording, never a dependency of it: if the model
/// assets are still downloading, the locale is unsupported, speech authorization is
/// refused, or the analyzer throws mid-session, `finish()` returns nil and the caller
/// falls back to transcribing the recorded file. Recording itself is unaffected, which is
/// why none of this reaches the UI (ARCHITECTURE.md §3.1.3).
///
/// Used only by `AudioRecordingService`, which owns its lifecycle.
actor LiveTranscriptionSession {
    /// v1 is English-only (ARCHITECTURE.md §2.3). When more locales land, this becomes a
    /// parameter rather than a constant.
    private static let locale = Locale(identifier: "en-US")

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Text the model has committed to and will not revise.
    private var finalizedText = ""
    /// The in-progress tail. The model revises this as more audio arrives, so it is
    /// replaced wholesale rather than appended to, and only folded into `finalizedText`
    /// once the model marks it final.
    private var volatileText = ""

    private var isRunning = false

    // MARK: DEBUG_LIVE_TRANSCRIPT — temporary; delete this property and every reference
    // to it (all inside this file, marked with the same token). The shipped design hands
    // the transcript over once, from `finish()`. `finalizedText` above accumulates
    // independently of this callback, so removing it cannot affect `finish()`.
    private let onUpdate: @Sendable (String) -> Void
    // MARK: END DEBUG_LIVE_TRANSCRIPT

    init(onUpdate: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onUpdate = onUpdate // DEBUG_LIVE_TRANSCRIPT
    }

    /// Downloads model assets if speech recognition is already authorized.
    ///
    /// Deliberately never prompts. This runs when the Speak screen merely appears, and
    /// asking for speech recognition before the user has expressed any intent to record
    /// is both startling and likely to get refused — the request belongs in
    /// `start(inputFormat:)`, behind an actual tap. The cost of skipping preparation is
    /// only that the first session installs assets slightly later.
    func prepare() async {
        guard isAlreadyAuthorized else { return }
        guard await SpeechTranscriber.supportedLocales.contains(where: Self.matchesLocale) else { return }

        let transcriber = makeTranscriber()
        guard await !SpeechTranscriber.installedLocales.contains(where: Self.matchesLocale) else { return }

        // `assetInstallationRequest` returns nil when nothing needs installing.
        guard let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        try? await request.downloadAndInstall()
    }

    /// Starts transcribing, prompting for speech authorization on the first attempt.
    /// `inputFormat` is the format buffers passed to `append(_:)` will be in.
    func start(inputFormat: AVAudioFormat) async {
        guard !isRunning else { return }
        guard await requestAuthorizationIfNeeded() else { return }
        guard await SpeechTranscriber.supportedLocales.contains(where: Self.matchesLocale) else { return }

        let transcriber = makeTranscriber()

        // The analyzer picks the format it wants; anything else has to be converted.
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        else { return }

        let (inputSequence, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        do {
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            inputContinuation.finish()
            return
        }

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.analyzerFormat = analyzerFormat
        self.converter = converter
        self.inputContinuation = inputContinuation
        self.isRunning = true

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    await self?.ingest(text: String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                // A mid-session analyzer failure keeps whatever was finalized so far.
                await self?.markStopped()
            }
        }
    }

    /// Feeds one buffer of captured audio. No-op when transcription is not running, so
    /// callers never need to check.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard isRunning, let converter, let analyzerFormat, let inputContinuation else { return }
        guard let converted = Self.convert(buffer, using: converter, to: analyzerFormat) else { return }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Stops transcription and returns the transcript.
    /// - Returns: the transcript, or nil if transcription never ran or produced nothing.
    func finish() async -> String? {
        guard isRunning else { return nil }
        isRunning = false

        inputContinuation?.finish()
        // Flushes audio already queued but not yet transcribed — without this the last
        // few seconds of speech are lost.
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value

        let transcript = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanUp()
        return transcript.isEmpty ? nil : transcript
    }

    /// Stops transcription and discards everything.
    func cancel() async {
        isRunning = false
        inputContinuation?.finish()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        finalizedText = ""
        volatileText = ""
        cleanUp()
    }

    // MARK: - Results

    private func ingest(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
        onUpdate(combinedText) // DEBUG_LIVE_TRANSCRIPT
    }

    private var combinedText: String {
        finalizedText + volatileText
    }

    private func markStopped() {
        isRunning = false
    }

    private func cleanUp() {
        resultsTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        analyzerFormat = nil
    }

    // MARK: - Helpers

    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: Self.locale,
            transcriptionOptions: [],
            // Volatile results are what make the transcript track speech in real time
            // instead of arriving in one lump at the end.
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    /// Whether speech recognition is authorized. Never prompts.
    private var isAlreadyAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Prompts only when the user has not been asked before.
    private func requestAuthorizationIfNeeded() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            // Refused or restricted. Re-asking would not prompt, and live transcription
            // is optional anyway — the recorded file still gets transcribed later.
            return false
        }
    }

    // Compares by language and region only — `SpeechTranscriber` reports locales with
    // extra components, so exact equality against "en-US" would miss valid matches.
    private static func matchesLocale(_ candidate: Locale) -> Bool {
        candidate.language.languageCode == locale.language.languageCode
            && candidate.region == locale.region
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        // Round up, and add a frame of slack: a fractional resampling ratio can emit one
        // more frame than the naive product, and an undersized buffer drops audio.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        // `convert(to:error:withInputFrom:)` invokes the block synchronously and returns
        // before this function does, so nothing here escapes or crosses a thread — but the
        // block is typed `@Sendable`, which the compiler cannot reconcile with either a
        // non-Sendable `AVAudioPCMBuffer` or a mutated capture. One `nonisolated(unsafe)`
        // local covers both, scoped to this single synchronous call, rather than marking a
        // whole type `@unchecked Sendable` (CLAUDE.md §6).
        //
        // The optional doubles as the take-once flag: the converter asks repeatedly until
        // it has enough input, and feeding the same buffer twice would duplicate audio.
        nonisolated(unsafe) var pending: AVAudioPCMBuffer? = buffer
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let next = pending else {
                status.pointee = .noDataNow
                return nil
            }
            pending = nil
            status.pointee = .haveData
            return next
        }

        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
