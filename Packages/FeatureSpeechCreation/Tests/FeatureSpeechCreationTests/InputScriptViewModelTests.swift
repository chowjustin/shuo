//
//  InputScriptViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

@testable import FeatureSpeechCreation
import Foundation
import ShuoCore
import ShuoTestSupport
import Testing

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
        capturer: FakeAudioCapturing = FakeAudioCapturing(),
        deleter: FakeAudioRecordingDeleting = FakeAudioRecordingDeleting(),
        transcriber: (any SpeechTranscribing)? = nil,
        repository: FakeScriptRepository = FakeScriptRepository(),
        initialText: String? = nil
    ) -> InputScriptViewModel {
        InputScriptViewModel(
            purpose: purpose,
            fileImporter: fileImporter ?? FakeFileImporting(returning: makeMedia()),
            makeAudioCapturer: { capturer },
            microphonePermissions: FakeMicrophonePermissionProviding(status: .granted),
            audioPlayer: FakeAudioPlaying(),
            recordingDeleter: deleter,
            generateTranscript: GenerateTranscriptUseCase(
                transcriber: transcriber ?? FakeSpeechTranscribing(returning: "Transcribed speech.")
            ),
            nextUntitledTitle: NextUntitledScriptTitleUseCase(repository: repository),
            initialText: initialText
        )
    }

    /// A saved script, for seeding the store so numbering has something to count.
    private func savedScript(titled title: String) -> Script {
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return Script(
            title: title,
            purpose: .persuade,
            transcript: Transcript(original: "A short speech about something."),
            createdAt: savedAt,
            updatedAt: savedAt
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

    // MARK: - initialText

    @Test("initial text opens in write mode with the text already in the editor")
    func initialTextOpensInWriteMode() {
        // A rejected transcript handed back for editing: the user already has the words,
        // and what they need is to change them, not to record the speech again.
        let viewModel = makeViewModel(initialText: "Remote work reshaped how our team collaborates.")

        #expect(viewModel.mode == .write)
        #expect(viewModel.writeVM.content == "Remote work reshaped how our team collaborates.")
        #expect(viewModel.hasValidContent, "the returned text should be ready to resubmit")
    }

    @Test("no initial text leaves the default speak mode with an empty editor")
    func absentInitialTextKeepsSpeakMode() {
        for initialText in [nil, ""] as [String?] {
            let viewModel = makeViewModel(initialText: initialText)

            #expect(viewModel.mode == .speak)
            #expect(viewModel.writeVM.content.isEmpty)
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
    func discardIsSafeWhenIdle() {
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

    // MARK: - Committing to one mode

    @Test("confirming keeps every mode, because transcription can still fail")
    func prepareToProceedPreservesTheOtherModes() async {
        // The user fills in all three and confirms on Speak. If transcription then fails
        // they come straight back here, and finding their typed text and attachment gone
        // would be losing work to a failure they did not cause.
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)
        viewModel.writeVM.content = "Typed draft."
        viewModel.mode = .attachFile
        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value
        viewModel.mode = .speak
        await recordAndPause(viewModel)

        _ = await viewModel.prepareToProceed()

        #expect(viewModel.writeVM.content == "Typed draft.")
        #expect(viewModel.attachVM.importedMedia != nil)
        #expect(await capturer.discardCount == 0)
    }

    @Test("the confirmed recording survives confirming, so going back can re-submit it")
    func confirmedRecordingSurvives() async {
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)
        await recordAndPause(viewModel)

        _ = await viewModel.prepareToProceed()

        // `.finished` still holds the take, and still satisfies the confirm button.
        #expect(viewModel.speakVM.viewState == .finished(FakeAudioCapturing.defaultRecording))
        #expect(viewModel.hasValidContent)
        #expect(await capturer.discardCount == 0)
    }

    @Test("every mode survives confirming, so stepping back finds the screen as it was")
    func confirmingKeepsEveryMode() async {
        // Confirming used to release the two modes the user did not pick. It cannot any
        // more: ‹ from the analysis screen comes back here, and it has to find the
        // recording, the typed draft and the attachment exactly where they were left.
        let capturer = FakeAudioCapturing()
        let viewModel = makeViewModel(capturer: capturer)
        viewModel.writeVM.content = "Typed draft."
        viewModel.mode = .attachFile
        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value
        viewModel.mode = .speak
        await recordAndPause(viewModel)

        _ = await viewModel.prepareToProceed()
        await viewModel.speakVM.transitionTask?.value

        #expect(viewModel.writeVM.content == "Typed draft.")
        #expect(viewModel.attachVM.importedMedia != nil)
        #expect(await capturer.discardCount == 0)
        #expect(viewModel.speakVM.viewState == .finished(FakeAudioCapturing.defaultRecording))
    }

    @Test("leaving the flow deletes the audio a confirmed take left on disk")
    func discardDeletesTheConfirmedRecording() async {
        // Nothing releases the take until the flow itself ends — and by then its capture
        // session has finished, so `discard()` can no longer reach the file. Deleting it
        // explicitly is the only thing that reclaims the storage.
        let capturer = FakeAudioCapturing()
        let deleter = FakeAudioRecordingDeleting()
        let viewModel = makeViewModel(capturer: capturer, deleter: deleter)
        await recordAndPause(viewModel)
        _ = await viewModel.prepareToProceed()

        viewModel.discard()
        await viewModel.speakVM.transitionTask?.value

        #expect(await deleter.deleted == [FakeAudioCapturing.defaultRecording])
    }

    // MARK: - Carrying a rejected transcript back

    @Test("a transcript handed back waits in Write mode without stealing the screen")
    func stashedTranscriptWaitsInWriteMode() async {
        // Stepping back lands the user in the mode they left — a recording they can still
        // play — but when analysis rejected the wording, the words are what needs changing,
        // so they are left within reach for a user who switches tabs to look.
        let viewModel = makeViewModel()
        await recordAndPause(viewModel)

        viewModel.stashTranscript("A speech about campus organizations.")

        #expect(viewModel.mode == .speak)
        #expect(viewModel.writeVM.content == "A speech about campus organizations.")
    }

    @Test("a stashed transcript never overwrites what the user typed")
    func stashedTranscriptDoesNotOverwriteTyping() async {
        let viewModel = makeViewModel()
        viewModel.writeVM.content = "My own draft."
        viewModel.mode = .speak
        await recordAndPause(viewModel)

        viewModel.stashTranscript("A transcript.")

        #expect(viewModel.writeVM.content == "My own draft.")
    }

    @Test("a transcript is not stashed into the mode that produced it")
    func stashedTranscriptSkipsWriteMode() {
        // In Write mode the transcript *is* what the user typed; writing it back would be
        // a no-op at best and a duplicate at worst.
        let viewModel = makeViewModel()
        viewModel.mode = .write

        viewModel.stashTranscript("A transcript.")

        #expect(viewModel.writeVM.content.isEmpty)
    }

    // MARK: - Warning before dropping other modes

    @Test("no other mode is flagged when only the active mode has content")
    func noUnconfirmedModesWhenOnlyActiveHasContent() async {
        let viewModel = makeViewModel()
        await recordAndPause(viewModel)

        #expect(viewModel.unconfirmedModesWithContent.isEmpty)
        #expect(viewModel.discardWarningMessage.isEmpty)
    }

    @Test("inactive modes that hold content are flagged, in catalog order")
    func flagsInactiveModesWithContent() async {
        let viewModel = makeViewModel()
        viewModel.writeVM.content = "Typed draft."
        viewModel.mode = .attachFile
        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value
        viewModel.mode = .speak
        await recordAndPause(viewModel)

        // Active mode is Speak; the other two both hold content, reported in
        // `InputMode.allCases` order (attachFile, write).
        #expect(viewModel.unconfirmedModesWithContent == [.attachFile, .write])
    }

    @Test("an empty inactive mode is not flagged")
    func ignoresEmptyInactiveModes() async {
        let viewModel = makeViewModel()
        viewModel.writeVM.content = "Typed draft."
        viewModel.mode = .speak
        await recordAndPause(viewModel)

        // Attach File was never touched, so only Write is at risk.
        #expect(viewModel.unconfirmedModesWithContent == [.write])
    }

    @Test("the warning message names the active mode and every mode that would be dropped")
    func warningMessageNamesTheModes() async {
        let viewModel = makeViewModel()
        viewModel.writeVM.content = "Typed draft."
        viewModel.mode = .attachFile
        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value
        viewModel.mode = .speak
        await recordAndPause(viewModel)

        let message = viewModel.discardWarningMessage
        #expect(message.contains(InputMode.speak.title))
        #expect(message.contains(InputMode.attachFile.title))
        #expect(message.contains(InputMode.write.title))
    }

    // MARK: - Untitled fallback

    @Test("a blank title falls back to the first numbered name in an empty library")
    func blankTitleFallsBackToFirstName() async {
        let viewModel = makeViewModel()

        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        #expect(viewModel.resolvedTitle == "Untitled Script 1")
    }

    @Test("the fallback numbers past the untitled scripts already saved")
    func fallbackNumbersPastSavedScripts() async {
        let repository = FakeScriptRepository(scripts: [
            savedScript(titled: "Untitled Script 1"),
            savedScript(titled: "Untitled Script 2"),
        ])
        let viewModel = makeViewModel(repository: repository)

        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        #expect(viewModel.resolvedTitle == "Untitled Script 3")
    }

    @Test("scripts the user named do not push the number along")
    func namedScriptsDoNotAffectTheNumber() async {
        let repository = FakeScriptRepository(scripts: [
            savedScript(titled: "Why remote work stuck"),
        ])
        let viewModel = makeViewModel(repository: repository)

        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        #expect(viewModel.resolvedTitle == "Untitled Script 1")
    }

    @Test("a title the user typed wins over the fallback")
    func typedTitleWinsOverFallback() async {
        let repository = FakeScriptRepository(scripts: [savedScript(titled: "Untitled Script 1")])
        let viewModel = makeViewModel(repository: repository)
        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        viewModel.title = "  Why remote work stuck  "

        #expect(viewModel.resolvedTitle == "Why remote work stuck")
    }

    @Test("a whitespace-only title is treated as blank")
    func whitespaceTitleIsBlank() async {
        let viewModel = makeViewModel()
        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        viewModel.title = "   \n "

        #expect(viewModel.resolvedTitle == "Untitled Script 1")
    }

    @Test("the draft carries the numbered name, so what analysis shows is what gets saved")
    func draftCarriesTheNumberedName() async {
        let repository = FakeScriptRepository(scripts: [savedScript(titled: "Untitled Script 4")])
        let viewModel = makeViewModel(repository: repository)
        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        let draft = viewModel.makeDraft(from: Transcript(original: "A speech."))

        #expect(draft.title == "Untitled Script 5")
    }

    @Test("a store that cannot be read still yields a usable name rather than blocking")
    func unreadableStoreFallsBackToFirstName() async {
        // The name of an untitled script is not worth failing the input step over; a store
        // this broken will report a real error at save time.
        let viewModel = makeViewModel(repository: FakeScriptRepository(throwing: .persistenceFailed))

        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        #expect(viewModel.resolvedTitle == "Untitled Script 1")
    }

    @Test("resolving twice does not renumber, so re-entering the step is safe")
    func resolvingIsIdempotent() async throws {
        // The step is re-entered rather than rebuilt, so its `.task` runs again on the way
        // back — by which point analysis has already saved this script under its name.
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value
        #expect(viewModel.resolvedTitle == "Untitled Script 1")

        try await repository.save(savedScript(titled: "Untitled Script 1"))
        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        #expect(viewModel.resolvedTitle == "Untitled Script 1")
    }

    @Test("stepping back adopts the number the script already has instead of renumbering")
    func restoringAdoptsTheExistingNumber() async {
        let repository = FakeScriptRepository(scripts: [savedScript(titled: "Untitled Script 3")])
        let viewModel = makeViewModel(repository: repository)

        viewModel.restoreTitle(from: "Untitled Script 3")
        // Whatever a later `.task` does, the adopted name has to survive it.
        viewModel.prepareUntitledPlaceholder()
        await viewModel.placeholderTask?.value

        #expect(viewModel.title.isEmpty)
        #expect(viewModel.resolvedTitle == "Untitled Script 3")
    }

    @Test("stepping back keeps a title the user typed")
    func restoringKeepsATypedTitle() {
        let viewModel = makeViewModel()

        viewModel.restoreTitle(from: "Why remote work stuck")

        #expect(viewModel.title == "Why remote work stuck")
    }

    @Test("a near-miss title is treated as the user's own, not as a placeholder")
    func restoringKeepsANearMissTitle() {
        let viewModel = makeViewModel()

        viewModel.restoreTitle(from: "Untitled Script ideas")

        #expect(viewModel.title == "Untitled Script ideas")
    }

    @Test("discarding the step abandons an in-flight name resolve")
    func discardCancelsThePlaceholderResolve() {
        let viewModel = makeViewModel()
        viewModel.prepareUntitledPlaceholder()

        viewModel.discard()

        #expect(viewModel.placeholderTask == nil)
    }
}
