//
//  CreateScriptCoordinatorTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore
import ShuoTestSupport
import Testing

@testable import FeatureSpeechCreation

@MainActor
@Suite("CreateScriptCoordinator")
struct CreateScriptCoordinatorTests {

    // MARK: - Fixtures

    private static let transcript = "A short speech about something."

    private static func draft(purpose: SpeechPurpose) -> ScriptDraft {
        ScriptDraft(
            title: "Untitled Script",
            purpose: purpose,
            transcript: Transcript(original: transcript)
        )
    }

    /// Records what the coordinator asked its factory to build, so tests can assert on the
    /// step it constructed rather than reaching into the view model it produced.
    @MainActor
    private final class InputFactory {
        private(set) var requests: [(purpose: SpeechPurpose, initialText: String?)] = []

        func make(_ purpose: SpeechPurpose, _ initialText: String?) -> InputScriptViewModel {
            requests.append((purpose, initialText))
            return InputScriptViewModel(
                purpose: purpose,
                fileImporter: FakeFileImporting(throwing: ShuoError.importFailed),
                makeAudioCapturer: { FakeAudioCapturing() },
                microphonePermissions: FakeMicrophonePermissionProviding(status: .granted),
                audioPlayer: FakeAudioPlaying(),
                recordingDeleter: FakeAudioRecordingDeleting(),
                generateTranscript: GenerateTranscriptUseCase(
                    transcriber: FakeSpeechTranscribing(returning: "")
                ),
                initialText: initialText
            )
        }
    }

    private func makeCoordinator(
        onFinish: @escaping () -> Void = {}
    ) -> (CreateScriptCoordinator, InputFactory) {
        let factory = InputFactory()
        let coordinator = CreateScriptCoordinator(
            onFinish: onFinish,
            makeInputScriptViewModel: factory.make
        )
        return (coordinator, factory)
    }

    /// Drives the coordinator to a live analysis step the way the flow reaches it: pick a
    /// purpose, write a speech, confirm, and hand transcription's result on.
    private func makeCoordinatorOnAnalysis(
        text: String = CreateScriptCoordinatorTests.transcript
    ) async -> (CreateScriptCoordinator, InputFactory, ScriptDraft) {
        let (coordinator, factory) = makeCoordinator()
        coordinator.selectPurpose(.persuade)
        let input = coordinator.inputViewModel
        input?.mode = .write
        input?.writeVM.content = text
        await coordinator.confirmInput()

        let draft = input?.makeDraft(from: Transcript(original: text))
            ?? Self.draft(purpose: .persuade)
        coordinator.beginAnalysis(draft)
        return (coordinator, factory, draft)
    }

    // MARK: - Stepping forward

    @Test("starts on the purpose step, with nothing selected and no input step built")
    func startsAtPurpose() {
        let (coordinator, factory) = makeCoordinator()

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.selectedPurpose == nil)
        #expect(coordinator.inputViewModel == nil)
        #expect(factory.requests.isEmpty)
    }

    @Test("selecting a purpose pushes the input step and builds it for that purpose")
    func selectPurposeBuildsTheInputStep() {
        let (coordinator, factory) = makeCoordinator()

        coordinator.selectPurpose(.persuade)

        #expect(coordinator.path == [.input])
        #expect(coordinator.selectedPurpose == .persuade)
        #expect(coordinator.inputViewModel?.purpose == .persuade)
        #expect(factory.requests.count == 1)
        // A fresh start seeds nothing — only a rebuilt step is handed text.
        #expect(factory.requests.first?.initialText == nil)
    }

    @Test("selecting another purpose replaces the previous step, never accumulates")
    func selectingAnotherPurposeReplacesTheFirst() {
        let (coordinator, _) = makeCoordinator()

        coordinator.selectPurpose(.inform)
        coordinator.selectPurpose(.inspire)

        #expect(coordinator.path == [.input])
        #expect(coordinator.selectedPurpose == .inspire)
        #expect(coordinator.inputViewModel?.purpose == .inspire)
    }

    @Test("confirming a mode with nothing in it leaves the user on the input step")
    func confirmingAnEmptyModeGoesNowhere() async {
        // Otherwise ✓ would strand them on a spinner with nothing to transcribe.
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)

        await coordinator.confirmInput()

        #expect(coordinator.path == [.input])
        #expect(coordinator.inputViewModel?.loadingVM == nil)
    }

    @Test("confirming real content opens the transcription step")
    func confirmingOpensTranscription() async {
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)
        coordinator.inputViewModel?.mode = .write
        coordinator.inputViewModel?.writeVM.content = Self.transcript

        await coordinator.confirmInput()

        #expect(coordinator.path == [.input, .loading])
        #expect(coordinator.inputViewModel?.loadingVM != nil)
    }

    @Test("beginning analysis keeps the input step alive behind it")
    func beginAnalysisKeepsTheInputStep() async {
        // The whole point of the back button on the analysis screen: the step behind it
        // still holds the user's recording, and stepping back has to find it there.
        let (coordinator, _, draft) = await makeCoordinatorOnAnalysis()

        #expect(coordinator.path == [.input, .analysis])
        #expect(coordinator.analysisDraft == draft)
        #expect(coordinator.inputViewModel != nil)
    }

    @Test("analysis replaces the transcription step rather than stacking on it")
    func beginAnalysisDropsTheLoadingStep() async {
        // ‹ from analysis belongs on Input Script, not on a loading screen the user has
        // already passed through.
        let (coordinator, _, _) = await makeCoordinatorOnAnalysis()

        #expect(!coordinator.path.contains(.loading))
    }

    // MARK: - Stepping back

    @Test("dismissing input script returns to purpose and drops the step")
    func dismissInputScriptReturnsToPurpose() {
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)

        coordinator.dismissInputScript()

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.selectedPurpose == nil)
        #expect(coordinator.inputViewModel == nil)
    }

    @Test("dismissing input script when already on purpose is a no-op")
    func dismissInputScriptWhenAlreadyAtPurposeIsANoOp() {
        let (coordinator, _) = makeCoordinator()

        coordinator.dismissInputScript()

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.selectedPurpose == nil)
    }

    @Test("leaving transcription keeps the same step, so nothing typed is rebuilt")
    func dismissLoadingKeepsTheLiveStep() async {
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)
        coordinator.inputViewModel?.title = "Draft title"
        coordinator.inputViewModel?.mode = .write
        coordinator.inputViewModel?.writeVM.content = Self.transcript
        await coordinator.confirmInput()
        let stepBefore = coordinator.inputViewModel

        coordinator.dismissLoading()

        #expect(coordinator.path == [.input])
        #expect(coordinator.inputViewModel?.title == "Draft title")
        #expect(coordinator.inputViewModel === stepBefore)
    }

    // MARK: - Back from analysis

    @Test("stepping back from analysis returns to the very same input step")
    func returnToInputResumesTheStep() async {
        // Rebuilding it would cost the user their recording, which is the one thing this
        // path exists to preserve.
        let (coordinator, factory, draft) = await makeCoordinatorOnAnalysis()
        let stepBefore = coordinator.inputViewModel

        coordinator.returnToInput(from: draft)

        #expect(coordinator.path == [.input])
        #expect(coordinator.inputViewModel === stepBefore)
        // One build, at selectPurpose — nothing was reconstructed on the way back.
        #expect(factory.requests.count == 1)
    }

    @Test("the analysis is retained on the way back, ready to be returned to")
    func returnToInputRetainsTheAnalysis() async {
        let (coordinator, _, draft) = await makeCoordinatorOnAnalysis()

        coordinator.returnToInput(from: draft)

        #expect(coordinator.analysisDraft == draft)
    }

    @Test("stepping back restores the title the analysis screen was showing")
    func returnToInputRestoresTheTitle() async {
        let (coordinator, _, _) = await makeCoordinatorOnAnalysis()
        var draft = Self.draft(purpose: .persuade)
        draft.title = "Why remote work stuck"

        coordinator.returnToInput(from: draft)

        #expect(coordinator.inputViewModel?.title == "Why remote work stuck")
    }

    @Test("the untitled placeholder is not restored as if the user had typed it")
    func returnToInputDoesNotRestoreThePlaceholder() async {
        // `makeDraft` substitutes this when the field was blank, so writing it back would
        // turn a placeholder into real content the user would have to delete.
        let (coordinator, _, _) = await makeCoordinatorOnAnalysis()
        var draft = Self.draft(purpose: .persuade)
        draft.title = InputScriptViewModel.untitledTitle

        coordinator.returnToInput(from: draft)

        #expect(coordinator.inputViewModel?.title.isEmpty == true)
    }

    @Test("a rejected transcript is left waiting in Write mode, not forced onto the screen")
    func returnToInputStashesTheTranscript() async {
        // The user recorded; they come back to their recording. The words are there if
        // they go looking for them, which is what a rejection asks them to do.
        let (coordinator, _, _) = await makeCoordinatorOnAnalysis(text: "Recorded speech.")
        coordinator.inputViewModel?.mode = .speak
        coordinator.inputViewModel?.writeVM.content = ""

        coordinator.returnToInput(from: Self.draft(purpose: .persuade))

        #expect(coordinator.inputViewModel?.mode == .speak)
        #expect(coordinator.inputViewModel?.writeVM.content == Self.transcript)
    }

    @Test("a released input step is rebuilt rather than stranding the user")
    func returnToInputRebuildsWhenThereIsNoStep() {
        let (coordinator, factory) = makeCoordinator()
        let draft = Self.draft(purpose: .inform)
        coordinator.beginAnalysis(draft)

        coordinator.returnToInput(from: draft)

        #expect(coordinator.path == [.input])
        #expect(coordinator.selectedPurpose == .inform)
        #expect(factory.requests.last?.initialText == Self.transcript)
        #expect(coordinator.inputViewModel?.mode == .write)
    }

    // MARK: - Confirming again after stepping back

    @Test("confirming unchanged input returns to the analysis instead of redoing it")
    func reconfirmingUnchangedInputSkipsTranscription() async {
        // The expensive half of this app is on-device generation. Reproducing an analysis
        // the user already has, for input they did not touch, is the one cost worth
        // engineering away here.
        let (coordinator, _, draft) = await makeCoordinatorOnAnalysis()
        coordinator.returnToInput(from: draft)

        await coordinator.confirmInput()

        #expect(coordinator.path == [.input, .analysis])
        // The same draft id is what lets the composition root hand back the same screen.
        #expect(coordinator.analysisDraft?.id == draft.id)
    }

    @Test("a rename made on the way back travels into the analysis being returned to")
    func reconfirmingCarriesARenameForward() async {
        let (coordinator, _, draft) = await makeCoordinatorOnAnalysis()
        coordinator.returnToInput(from: draft)
        coordinator.inputViewModel?.title = "Why remote work stuck"

        await coordinator.confirmInput()

        #expect(coordinator.analysisDraft?.title == "Why remote work stuck")
        #expect(coordinator.analysisDraft?.id == draft.id)
    }

    @Test("confirming changed input transcribes again rather than reusing the analysis")
    func reconfirmingChangedInputStartsOver() async {
        let (coordinator, _, draft) = await makeCoordinatorOnAnalysis()
        coordinator.returnToInput(from: draft)
        coordinator.inputViewModel?.writeVM.content = "An entirely different speech."

        await coordinator.confirmInput()

        #expect(coordinator.path == [.input, .loading])
        #expect(coordinator.analysisDraft == nil)
    }

    // MARK: - Leaving

    @Test("close invokes the finish callback")
    func closeInvokesOnFinish() {
        var finished = false
        let (coordinator, _) = makeCoordinator(onFinish: { finished = true })

        coordinator.close()

        #expect(finished)
    }

    @Test("close invokes the finish callback from any step, and releases the input step")
    func closeInvokesOnFinishFromAnyStep() {
        var finished = false
        let (coordinator, _) = makeCoordinator(onFinish: { finished = true })

        coordinator.selectPurpose(.persuade)
        coordinator.close()

        #expect(finished)
        // Leaving must not strand a live recorder behind a dismissed sheet.
        #expect(coordinator.inputViewModel == nil)
        #expect(coordinator.path.isEmpty)
    }

    @Test("close from analysis releases the retained analysis too")
    func closeFromAnalysisReleasesEverything() async {
        // This is the moment the recording is deleted, so nothing may outlive it still
        // pointing at a file that is gone.
        let (coordinator, _, _) = await makeCoordinatorOnAnalysis()

        coordinator.close()

        #expect(coordinator.analysisDraft == nil)
        #expect(coordinator.inputViewModel == nil)
        #expect(coordinator.path.isEmpty)
    }
}
