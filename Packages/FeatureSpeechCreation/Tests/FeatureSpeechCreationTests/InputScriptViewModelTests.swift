//
//  InputScriptViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

import Testing
import Foundation
import ShuoCore
import ShuoTestSupport
@testable import FeatureSpeechCreation

@MainActor
@Suite("InputScriptViewModel")
struct InputScriptViewModelTests {

    private func makeMedia() -> ImportedMedia {
        ImportedMedia(
            fileURL: URL(filePath: "/tmp/speech.m4a"),
            kind: .audio,
            originalFileName: "speech.m4a"
        )
    }

    private func makeViewModel(
        purpose: SpeechPurpose = .persuade,
        fileImporter: (any FileImporting)? = nil,
        capturer: FakeAudioCapturing = FakeAudioCapturing()
    ) -> InputScriptViewModel {
        InputScriptViewModel(
            purpose: purpose,
            fileImporter: fileImporter ?? FakeFileImporting(returning: makeMedia()),
            audioCapturer: capturer,
            microphonePermissions: FakeMicrophonePermissionProviding(status: .granted)
        )
    }

    /// Drives Speak mode to `.paused` with audio captured — the point at which the user
    /// is allowed to proceed.
    private func recordAndPause(_ viewModel: InputScriptViewModel) async {
        viewModel.speakVM.primaryAction()
        await viewModel.speakVM.transitionTask?.value
        viewModel.speakVM.handle(.tick(amplitudes: [0.5], duration: 3))
        viewModel.speakVM.primaryAction()
        await viewModel.speakVM.transitionTask?.value
    }

    @Test("defaults to speak mode")
    func defaultsToSpeakMode() {
        #expect(makeViewModel().mode == .speak)
    }

    @Test("retains the purpose it was initialized with")
    func retainsInjectedPurpose() {
        #expect(makeViewModel(purpose: .inspire).purpose == .inspire)
    }

    @Test("mode switches to every input mode")
    func modeSwitchesToEachCase() {
        let viewModel = makeViewModel(purpose: .inform)

        for mode in InputMode.allCases {
            viewModel.mode = mode
            #expect(viewModel.mode == mode)
        }
    }

    // MARK: - hasValidContent

    @Test("hasValidContent is false in every mode before anything is entered")
    func hasValidContentFalseWhenUntouched() {
        let viewModel = makeViewModel()

        for mode in InputMode.allCases {
            viewModel.mode = mode
            #expect(!viewModel.hasValidContent)
        }
    }

    @Test("hasValidContent is false in attachFile mode before a file is imported")
    func hasValidContentFalseWhenIdle() {
        let viewModel = makeViewModel()
        viewModel.mode = .attachFile

        #expect(!viewModel.hasValidContent)
    }

    @Test("hasValidContent is true in attachFile mode after a successful import")
    func hasValidContentTrueAfterImport() async {
        let viewModel = makeViewModel()
        viewModel.mode = .attachFile

        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value

        #expect(viewModel.hasValidContent)
    }

    @Test("hasValidContent is false in attachFile mode after a failed import")
    func hasValidContentFalseAfterFailedImport() async {
        let viewModel = makeViewModel(fileImporter: FakeFileImporting(throwing: ShuoError.importFailed))
        viewModel.mode = .attachFile

        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value

        #expect(!viewModel.hasValidContent)
    }

    @Test("hasValidContent is true in write mode once something is typed")
    func hasValidContentTrueAfterTyping() {
        let viewModel = makeViewModel()
        viewModel.mode = .write

        viewModel.writeVM.content = "Why we must join campus organizations."

        #expect(viewModel.hasValidContent)
    }

    @Test("hasValidContent is false in write mode for whitespace alone")
    func hasValidContentFalseForWhitespace() {
        let viewModel = makeViewModel()
        viewModel.mode = .write

        viewModel.writeVM.content = "   \n  "

        #expect(!viewModel.hasValidContent)
    }

    @Test("hasValidContent is false in speak mode while still recording")
    func hasValidContentFalseWhileRecording() async {
        let viewModel = makeViewModel()

        viewModel.speakVM.primaryAction()
        await viewModel.speakVM.transitionTask?.value
        viewModel.speakVM.handle(.tick(amplitudes: [0.5], duration: 3))

        #expect(!viewModel.hasValidContent)
    }

    @Test("hasValidContent is true in speak mode once paused with audio captured")
    func hasValidContentTrueWhenPaused() async {
        let viewModel = makeViewModel()

        await recordAndPause(viewModel)

        #expect(viewModel.hasValidContent)
    }

    @Test("hasValidContent follows the active mode, not whichever mode has content")
    func hasValidContentFollowsActiveMode() async {
        // Recording then switching to an empty Write tab must not leave the confirm
        // button enabled against content the user cannot see.
        let viewModel = makeViewModel()
        await recordAndPause(viewModel)
        #expect(viewModel.hasValidContent)

        viewModel.mode = .write
        #expect(!viewModel.hasValidContent)

        viewModel.mode = .speak
        #expect(viewModel.hasValidContent)
    }

    // MARK: - discard

    @Test("discard ends an in-flight speak session rather than leaving the microphone live")
    func discardEndsSpeakSession() async {
        // Leaving the screen without confirming must not leave the audio engine running
        // behind a screen the user has already left.
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)
        viewModel.speakVM.primaryAction()
        await viewModel.speakVM.transitionTask?.value

        viewModel.discard()
        await viewModel.speakVM.transitionTask?.value

        #expect(await capturer.discardCount == 1)
        #expect(viewModel.speakVM.viewState == .idle)
        #expect(!viewModel.hasValidContent)
    }

    @Test("discard clears an imported file")
    func discardClearsImportedFile() async {
        let viewModel = makeViewModel()
        viewModel.mode = .attachFile
        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value

        viewModel.discard()

        #expect(!viewModel.hasValidContent)
        #expect(viewModel.attachVM.importedMedia == nil)
    }

    @Test("discard is safe when nothing has been started")
    func discardIsSafeWhenIdle() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)

        viewModel.discard()

        #expect(viewModel.speakVM.viewState == .idle)
    }

    // MARK: - prepareToProceed

    @Test("prepareToProceed returns recorded audio in speak mode")
    func prepareToProceedReturnsRecordedAudio() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)
        await recordAndPause(viewModel)

        let source = await viewModel.prepareToProceed()

        #expect(source == .recordedAudio(FakeAudioCapturing.defaultRecording))
        // The session must actually be ended, not just read.
        #expect(await capturer.finishCount == 1)
    }

    @Test("prepareToProceed returns typed text in write mode")
    func prepareToProceedReturnsTypedText() async {
        let viewModel = makeViewModel()
        viewModel.mode = .write
        viewModel.writeVM.content = "Why we must join campus organizations."

        let source = await viewModel.prepareToProceed()

        #expect(source == .typedText("Why we must join campus organizations."))
    }

    @Test("prepareToProceed returns imported media in attachFile mode")
    func prepareToProceedReturnsImportedMedia() async {
        let media = makeMedia()
        let viewModel = makeViewModel(fileImporter: FakeFileImporting(returning: media))
        viewModel.mode = .attachFile
        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value

        let source = await viewModel.prepareToProceed()

        #expect(source == .importedMedia(media))
    }

    @Test("prepareToProceed returns nothing when the active mode has no content")
    func prepareToProceedReturnsNilWhenEmpty() async {
        let viewModel = makeViewModel()

        for mode in InputMode.allCases {
            viewModel.mode = mode
            #expect(await viewModel.prepareToProceed() == nil)
        }
    }

    @Test("prepareToProceed does not end a speak session that is still recording")
    func prepareToProceedIgnoresLiveRecording() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)
        viewModel.speakVM.primaryAction()
        await viewModel.speakVM.transitionTask?.value
        viewModel.speakVM.handle(.tick(amplitudes: [0.5], duration: 3))

        let source = await viewModel.prepareToProceed()

        #expect(source == nil)
        #expect(await capturer.finishCount == 0)
    }
}
