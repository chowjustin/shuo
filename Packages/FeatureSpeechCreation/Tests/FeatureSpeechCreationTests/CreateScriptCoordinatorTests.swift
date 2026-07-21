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
                audioCapturer: FakeAudioCapturing(),
                microphonePermissions: FakeMicrophonePermissionProviding(status: .granted),
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

    // MARK: - Stepping forward

    @Test("starts on the purpose step, with nothing selected and no input step built")
    func startsAtPurpose() {
        let (coordinator, factory) = makeCoordinator()

        #expect(coordinator.step == .purpose)
        #expect(coordinator.selectedPurpose == nil)
        #expect(coordinator.inputViewModel == nil)
        #expect(factory.requests.isEmpty)
    }

    @Test("selecting a purpose moves to the input step and builds it for that purpose")
    func selectPurposeBuildsTheInputStep() {
        let (coordinator, factory) = makeCoordinator()

        coordinator.selectPurpose(.persuade)

        #expect(coordinator.step == .input)
        #expect(coordinator.selectedPurpose == .persuade)
        #expect(coordinator.inputViewModel?.purpose == .persuade)
        #expect(factory.requests.count == 1)
        // A fresh start seeds nothing — only the rejection path passes text.
        #expect(factory.requests.first?.initialText == nil)
    }

    @Test("selecting another purpose replaces the previous step, never accumulates")
    func selectingAnotherPurposeReplacesTheFirst() {
        let (coordinator, _) = makeCoordinator()

        coordinator.selectPurpose(.inform)
        coordinator.selectPurpose(.inspire)

        #expect(coordinator.selectedPurpose == .inspire)
        #expect(coordinator.inputViewModel?.purpose == .inspire)
    }

    @Test("the loading step is refused until there is transcription work to show")
    func beginLoadingRequiresWork() {
        // Otherwise ✓ on an empty mode would strand the user on a spinner with nothing
        // behind it.
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)

        coordinator.beginLoading()

        #expect(coordinator.step == .input)
    }

    @Test("beginning analysis is where unconfirmed modes are released, not confirming")
    func beginAnalysisDiscardsUnconfirmedModes() async {
        // Everything before this point is reversible — a failed transcription returns to a
        // step with all three modes intact. Analysis is the first moment nothing can reach
        // them, which is why the release happens here and not at confirm time.
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)
        let input = try! #require(coordinator.inputViewModel)
        input.writeVM.content = "Typed draft."
        input.mode = .speak

        coordinator.beginAnalysis(Self.draft(purpose: .persuade))

        #expect(input.writeVM.content.isEmpty)
    }

    @Test("beginning analysis replaces the input step rather than keeping it alive")
    func beginAnalysisReleasesTheInputStep() {
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)
        let draft = Self.draft(purpose: .persuade)

        coordinator.beginAnalysis(draft)

        #expect(coordinator.step == .analysis(draft))
        #expect(coordinator.analysisDraft == draft)
        // Held state would keep an abandoned recorder alive behind the analysis screen.
        #expect(coordinator.inputViewModel == nil)
    }

    // MARK: - Stepping back

    @Test("dismissing input script returns to purpose and drops the step")
    func dismissInputScriptReturnsToPurpose() {
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)

        coordinator.dismissInputScript()

        #expect(coordinator.step == .purpose)
        #expect(coordinator.selectedPurpose == nil)
        #expect(coordinator.inputViewModel == nil)
    }

    @Test("dismissing input script when already on purpose is a no-op")
    func dismissInputScriptWhenAlreadyAtPurposeIsANoOp() {
        let (coordinator, _) = makeCoordinator()

        coordinator.dismissInputScript()

        #expect(coordinator.step == .purpose)
        #expect(coordinator.selectedPurpose == nil)
    }

    // MARK: - Returning a rejected transcript to Input Script

    @Test("returning a rejected draft leaves analysis and reopens Input Script on its purpose")
    func returnToInputRestoresThePurpose() {
        // The one place the flow moves backwards: "this isn't a speech" is precisely the
        // verdict whose fix lives on the earlier screen.
        let (coordinator, _) = makeCoordinator()
        let draft = Self.draft(purpose: .inspire)
        coordinator.beginAnalysis(draft)

        coordinator.returnToInput(rejecting: draft)

        #expect(coordinator.step == .input)
        #expect(coordinator.analysisDraft == nil)
        #expect(coordinator.selectedPurpose == .inspire)
    }

    @Test("the rejected transcript seeds the rebuilt step, so the user does not re-record it")
    func returnToInputSeedsTheTranscript() {
        let (coordinator, factory) = makeCoordinator()
        let draft = Self.draft(purpose: .inform)

        coordinator.returnToInput(rejecting: draft)

        #expect(factory.requests.last?.initialText == Self.transcript)
        #expect(coordinator.inputViewModel?.writeVM.content == Self.transcript)
        // Write mode, not Speak: the user already has the words and needs to change them.
        #expect(coordinator.inputViewModel?.mode == .write)
    }

    @Test("a rebuilt step is a fresh one, so the transcript is not resurrected later")
    func rebuiltStepDoesNotLeakIntoTheNextSpeech() {
        // Read-once by construction: the seed is passed at build time rather than parked on
        // the coordinator, so returning to Purpose and starting over cannot pick it up.
        let (coordinator, factory) = makeCoordinator()
        coordinator.returnToInput(rejecting: Self.draft(purpose: .inform))

        coordinator.dismissInputScript()
        coordinator.selectPurpose(.inform)

        #expect(factory.requests.last?.initialText == nil)
        #expect(coordinator.inputViewModel?.writeVM.content.isEmpty == true)
        #expect(coordinator.inputViewModel?.mode == .speak)
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
    }
    // MARK: - Carrying the user's typing back

    @Test("returning from analysis restores the title the user typed")
    func returnToInputRestoresTheTitle() {
        // The step is rebuilt rather than resumed, so anything typed has to be carried back
        // explicitly or it is silently lost on the way out of a failure.
        let (coordinator, _) = makeCoordinator()
        var draft = Self.draft(purpose: .inform)
        draft.title = "Why remote work stuck"

        coordinator.returnToInput(rejecting: draft)

        #expect(coordinator.inputViewModel?.title == "Why remote work stuck")
    }

    @Test("the untitled placeholder is not restored as if the user had typed it")
    func returnToInputDoesNotRestoreThePlaceholder() {
        // `makeDraft` substitutes this when the field was blank, so writing it back would
        // turn a placeholder into real content the user would have to delete.
        let (coordinator, _) = makeCoordinator()
        var draft = Self.draft(purpose: .inform)
        draft.title = InputScriptViewModel.untitledTitle

        coordinator.returnToInput(rejecting: draft)

        #expect(coordinator.inputViewModel?.title.isEmpty == true)
    }

    @Test("returning from transcription keeps the same step, so the title is never rebuilt")
    func dismissLoadingKeepsTheTypedTitle() {
        // The other back path. It reuses the live step rather than rebuilding it, so this
        // guards against a future refactor quietly making it rebuild too.
        let (coordinator, _) = makeCoordinator()
        coordinator.selectPurpose(.persuade)
        coordinator.inputViewModel?.title = "Draft title"
        let stepBefore = coordinator.inputViewModel

        coordinator.dismissLoading()

        #expect(coordinator.inputViewModel?.title == "Draft title")
        #expect(coordinator.inputViewModel === stepBefore)
    }

}
