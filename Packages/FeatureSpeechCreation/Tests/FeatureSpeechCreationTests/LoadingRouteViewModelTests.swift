//
//  LoadingRouteViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 20/07/26.
//

import Testing
import Foundation
import ShuoCore
import ShuoTestSupport
@testable import FeatureSpeechCreation

@MainActor
@Suite("LoadingRouteViewModel")
struct LoadingRouteViewModelTests {

    // MARK: - Helpers

    private func makeMedia(kind: ImportedMedia.Kind = .audio) -> ImportedMedia {
        ImportedMedia(
            fileURL: URL(filePath: "/tmp/speech.m4a"),
            kind: kind,
            originalFileName: kind == .video ? "speech.mov" : "speech.m4a",
            duration: 42
        )
    }

    private func makeViewModel(
        source: SpeechSource? = nil,
        transcriber: FakeSpeechTranscribing = FakeSpeechTranscribing(returning: "Transcribed speech.")
    ) -> LoadingRouteViewModel {
        LoadingRouteViewModel(
            source: source ?? .importedMedia(makeMedia()),
            generateTranscript: GenerateTranscriptUseCase(transcriber: transcriber)
        )
    }

    /// Lets the view model's detached work run to completion.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: - Initial state

    @Test("An audio attachment starts on the transcribing step")
    func audioStartsTranscribing() {
        let sut = makeViewModel()
        sut.start()
        #expect(sut.viewState == .loading(.transcribing))
    }

    @Test("A video attachment starts on the extracting-audio step")
    func videoStartsExtracting() {
        let sut = makeViewModel(source: .importedMedia(makeMedia(kind: .video)))
        sut.start()
        #expect(sut.viewState == .loading(.extractingAudio))
    }

    @Test("The attachment's filename is exposed for the loading screen's detail line")
    func exposesFileName() {
        let sut = makeViewModel()
        #expect(sut.sourceDescription == "speech.m4a")
    }

    @Test("A typed-text source has no filename to show")
    func typedTextHasNoFileName() {
        let sut = makeViewModel(source: .typedText("Some written speech."))
        #expect(sut.sourceDescription == nil)
    }

    // MARK: - Success

    @Test("A successful transcription finishes with the transcript")
    func successFinishes() async {
        let sut = makeViewModel()
        sut.start()
        await settle()

        #expect(sut.viewState == .finished(Transcript(original: "Transcribed speech.")))
        #expect(sut.transcript?.original == "Transcribed speech.")
        #expect(sut.failure == nil)
    }

    // MARK: - Failure

    @Test("A transcription failure surfaces the domain error for the error sheet")
    func failureSurfacesDomainError() async {
        let sut = makeViewModel(transcriber: FakeSpeechTranscribing(throwing: .audioExtractionFailed))
        sut.start()
        await settle()

        #expect(sut.viewState == .failed(.audioExtractionFailed))
        #expect(sut.failure == .audioExtractionFailed)
        #expect(sut.transcript == nil)
    }

    @Test("Silent media is reported as no speech detected rather than a generic failure")
    func silentMediaReportsNoSpeech() async {
        let sut = makeViewModel(transcriber: FakeSpeechTranscribing(returning: "   "))
        sut.start()
        await settle()

        #expect(sut.failure == .noSpeechDetected)
    }

    @Test("Retrying after a failure returns to the loading state")
    func retryReturnsToLoading() async {
        let sut = makeViewModel(transcriber: FakeSpeechTranscribing(throwing: .transcriptionFailed))
        sut.start()
        await settle()
        #expect(sut.failure == .transcriptionFailed)

        sut.start()
        #expect(sut.viewState == .loading(.transcribing))
    }

    // MARK: - Cancellation
    //
    // The bug class CLAUDE.md §6 calls out for this app specifically: work that outlives
    // the screen that asked for it.

    @Test("Cancelling stops the in-flight transcription from landing in the view state")
    func cancelPreventsLateStateChange() async {
        let sut = makeViewModel(
            transcriber: FakeSpeechTranscribing(returning: "Too late.", after: .milliseconds(80))
        )
        sut.start()
        sut.cancel()

        try? await Task.sleep(for: .milliseconds(200))

        #expect(sut.viewState == .loading(.transcribing))
        #expect(sut.transcript == nil)
        #expect(sut.failure == nil)
    }

    @Test("Restarting cancels the previous attempt so only the newest result is used")
    func restartSupersedesPreviousAttempt() async {
        let sut = makeViewModel(
            transcriber: FakeSpeechTranscribing(returning: "Final result.", after: .milliseconds(50))
        )
        sut.start()
        sut.start()

        try? await Task.sleep(for: .milliseconds(250))

        #expect(sut.transcript?.original == "Final result.")
    }
}
