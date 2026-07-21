//
//  TranscriptAnalysisViewModelTests.swift
//  FeatureTranscriptAnalysisTests
//
//  Created by Justin Chow on 13/07/26.
//

// `@MainActor` Swift Testing suite for `TranscriptAnalysisViewModel`: the classify →
// key points → prefetch → refine flow, per-pattern caching, and — most importantly —
// cancellation, against fakes from ShuoTestSupport. See ARCHITECTURE.md §8.

import Foundation
import Testing
import ShuoCore
import ShuoTestSupport
@testable import FeatureTranscriptAnalysis

@MainActor
@Suite("Transcript analysis view model")
struct TranscriptAnalysisViewModelTests {

    // MARK: - Fixtures

    /// Comfortably past the usability precheck, so tests exercise the model path.
    private static let transcript = """
        Good morning everyone. Today I want to talk about why remote work has reshaped \
        how our team collaborates. When we moved to a distributed model two years ago, \
        we assumed productivity would fall. It didn't. What actually changed was the \
        shape of our communication, and that turned out to matter far more than the \
        number of hours anyone logged at a desk each week.
        """

    /// The three inform patterns these tests rank, in prefetch order.
    private static let rankedIDs = ["inform.topical", "inform.causeEffect", "inform.spatial"]

    private func makeDraft() -> ScriptDraft {
        ScriptDraft(
            title: "Why remote work stuck",
            purpose: .inform,
            transcript: Transcript(original: Self.transcript)
        )
    }

    private func makeViewModel(
        analyzer: FakeSpeechAnalyzing,
        repository: FakeScriptRepository = FakeScriptRepository(),
        availability: any AIAvailabilityChecking = FakeAIAvailabilityChecking(.available)
    ) -> TranscriptAnalysisViewModel {
        let viewModel = TranscriptAnalysisViewModel(
            draft: makeDraft(),
            availability: availability,
            classifyTranscript: ClassifyTranscriptUseCase(analyzer: analyzer),
            generateKeyPoints: GenerateKeyPointsUseCase(analyzer: analyzer),
            regenerateTranscript: RegenerateTranscriptUseCase(analyzer: analyzer),
            saveScript: SaveScriptUseCase(repository: repository)
        )
        // The shipping interval is 2s, tuned for a real asset download. Tests assert the
        // *behaviour* of the poll, not its pacing, so shrink it rather than sleeping.
        viewModel.availabilityPollInterval = .milliseconds(10)
        return viewModel
    }

    private func makeAnalyzer(
        ranked: [String] = TranscriptAnalysisViewModelTests.rankedIDs,
        delay: Duration = .zero
    ) -> FakeSpeechAnalyzing {
        FakeSpeechAnalyzing(
            classification: .success(.usable(rankedPatternIDs: ranked)),
            delay: delay
        )
    }

    /// Polls until `condition` holds, so tests wait on observable state rather than on a
    /// fixed sleep. The view model's work runs in detached tasks with no completion handle
    /// to await, and a fixed sleep would be both slower and flakier.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for the expected state")
    }

    // MARK: - Initial analysis

    @Test("Analysis loads the ranked patterns and the top pattern's key points")
    func loadsTopPattern() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        #expect(viewModel.carousel.patterns.map(\.id) == Self.rankedIDs)
        #expect(viewModel.selectedPattern?.id == "inform.topical")
        #expect(!viewModel.keyPoints.isEmpty)
    }

    @Test("The top pattern's key points cover every one of its components")
    func keyPointsAreComplete() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        let topical = try #require(SpeechPatternCatalog.pattern(id: "inform.topical"))
        #expect(viewModel.keyPoints.map(\.componentID) == topical.components.map(\.id))
    }

    @Test("The top pattern's key points are requested before any other")
    func topPatternIsGeneratedFirst() async throws {
        // The whole point of the eager-first schedule: the user waits only for pattern #1.
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        let calls = await analyzer.keyPointCalls
        #expect(calls.first == "inform.topical")
    }

    @Test("The suggested pattern ids are recorded on the draft")
    func draftRecordsSuggestions() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        #expect(viewModel.draft.suggestedPatternIDs == Self.rankedIDs)
        #expect(viewModel.draft.selectedPatternID == "inform.topical")
    }

    @Test("Calling start twice does not run a second classification")
    func startIsIdempotent() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        let count = await analyzer.classifyCallCount
        #expect(count == 1)
    }

    // MARK: - AI availability

    @Test("A model that isn't ready yet waits instead of calling the analyzer")
    func modelNotReadyWaits() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(
            analyzer: analyzer,
            availability: FakeAIAvailabilityChecking(.modelNotReady)
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .waitingForModel }
        // Several poll intervals: enough that a gate that let the call through anyway would
        // have done so by now.
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.viewState == .waitingForModel)
        let count = await analyzer.classifyCallCount
        #expect(count == 0, "classification ran before the model was ready")
    }

    @Test("Analysis continues on its own once the model becomes ready")
    func modelBecomesReady() async throws {
        // The point of polling rather than failing: the user does nothing and the screen
        // moves forward by itself.
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(
            analyzer: analyzer,
            availability: FakeAIAvailabilityChecking(
                sequence: [.modelNotReady, .modelNotReady, .available]
            )
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .waitingForModel }
        try await waitUntil { viewModel.viewState == .loaded }

        #expect(viewModel.selectedPattern?.id == "inform.topical")
        #expect(!viewModel.keyPoints.isEmpty)
    }

    @Test("cancelAll stops the availability poll rather than leaving it running")
    func cancelAllStopsThePoll() async throws {
        // A poll that outlives the screen would keep waking up forever, and would run the
        // analysis into a sheet the user has already dismissed (CLAUDE.md §6).
        let analyzer = makeAnalyzer()
        let availability = FakeAIAvailabilityChecking(.modelNotReady)
        let viewModel = makeViewModel(analyzer: analyzer, availability: availability)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .waitingForModel }
        viewModel.cancelAll()

        // Let any check already in flight when cancel landed finish, then take the reading.
        try await Task.sleep(for: .milliseconds(60))
        let afterCancel = await availability.callCount
        // ~30 poll intervals. A live poll would be plainly ahead of the snapshot by now.
        try await Task.sleep(for: .milliseconds(300))

        let later = await availability.callCount
        #expect(later == afterCancel, "the availability poll kept running after cancellation")
        let count = await analyzer.classifyCallCount
        #expect(count == 0, "analysis ran after the screen was torn down")
    }

    @Test("Apple Intelligence being switched off is a terminal state, not a wait")
    func appleIntelligenceOffIsTerminal() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(
            analyzer: analyzer,
            availability: FakeAIAvailabilityChecking(.appleIntelligenceNotEnabled)
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .unavailable(.appleIntelligenceNotEnabled) }
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.viewState == .unavailable(.appleIntelligenceNotEnabled))
        let count = await analyzer.classifyCallCount
        #expect(count == 0)
    }

    @Test("Ineligible hardware is its own state, distinct from Apple Intelligence being off")
    func deviceNotEligibleIsItsOwnState() async throws {
        // Both are dead ends, but one is a Settings toggle and the other is the device, so
        // flattening them into a single state would guarantee wrong advice for one of them.
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(
            analyzer: analyzer,
            availability: FakeAIAvailabilityChecking(.deviceNotEligible)
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .unavailable(.deviceNotEligible) }

        #expect(viewModel.viewState != .unavailable(.appleIntelligenceNotEnabled))
        let count = await analyzer.classifyCallCount
        #expect(count == 0)
    }

    @Test("An unavailable model is never reported as a rejection of the user's transcript")
    func unavailableIsNotARejection() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(
            analyzer: analyzer,
            availability: FakeAIAvailabilityChecking(.appleIntelligenceNotEnabled)
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .unavailable(.appleIntelligenceNotEnabled) }

        if case .rejected = viewModel.viewState {
            Issue.record("a device-side problem was blamed on the user's content")
        }
    }

    // MARK: - Title

    @Test("Renaming the script writes through to the draft and marks it unsaved")
    func titleIsEditable() async throws {
        // Without this the input step's optional title is permanent: a user who skipped it
        // has no rename path anywhere in the app.
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }
        #expect(!viewModel.hasUnsavedChanges)

        viewModel.title = "Why remote work stuck, actually"

        #expect(viewModel.draft.title == "Why remote work stuck, actually")
        #expect(viewModel.title == "Why remote work stuck, actually")
        #expect(viewModel.hasUnsavedChanges)
    }

    @Test("A rename is persisted by the next save")
    func renameIsSaved() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        viewModel.title = "A better name"
        viewModel.save()
        try await waitUntil { await repository.saveCount == 2 }

        let scripts = await repository.scripts
        #expect(scripts.count == 1)
        #expect(scripts.first?.title == "A better name")
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("Setting the same title again does not invent unsaved changes")
    func settingTheSameTitleIsANoOp() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        // The binding behind the title field writes on every keystroke, so an unchanged
        // value must not put the leave-confirmation dialog in the user's way.
        viewModel.title = viewModel.title

        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("Clearing the title falls back to Untitled Script once the edit is committed")
    func clearedTitleFallsBackOnCommit() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        // Mid-edit the field is allowed to be empty — the user is clearing it to retype,
        // and snapping the placeholder back under the cursor would fight them.
        viewModel.title = ""
        #expect(viewModel.title.isEmpty)

        viewModel.commitTitle()

        #expect(viewModel.title == TranscriptAnalysisViewModel.untitledTitle)
        #expect(viewModel.draft.title == TranscriptAnalysisViewModel.untitledTitle)
    }

    @Test("A whitespace-only title is treated as empty, not saved as spaces")
    func whitespaceOnlyTitleFallsBack() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        viewModel.title = "   \n "
        viewModel.commitTitle()

        #expect(viewModel.title == TranscriptAnalysisViewModel.untitledTitle)
    }

    @Test("Committing trims surrounding whitespace from a real title")
    func commitTrimsTitle() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        viewModel.title = "  A better name  "
        viewModel.commitTitle()

        #expect(viewModel.title == "A better name")
    }

    @Test("Committing an already-clean title does not invent unsaved changes")
    func commitOnCleanTitleIsANoOp() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }
        #expect(!viewModel.hasUnsavedChanges)

        // The field commits on every focus loss, including ones where nothing was typed.
        viewModel.commitTitle()

        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("An empty title is never persisted, even when saved straight from the keyboard")
    func emptyTitleIsNeverPersisted() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        // ✓ can be tapped without the field ever losing focus, so `save` has to settle the
        // title itself rather than trusting the view to have done it.
        viewModel.title = ""
        viewModel.save()
        try await waitUntil { await repository.saveCount == 2 }

        let scripts = await repository.scripts
        #expect(scripts.count == 1)
        #expect(scripts.first?.title == TranscriptAnalysisViewModel.untitledTitle)
        #expect(!viewModel.hasUnsavedChanges)
    }

    // MARK: - Rejection and failure

    @Test("An unusable transcript lands on the rejected state with its reason")
    func rejectedTranscript() async throws {
        let analyzer = FakeSpeechAnalyzing(classification: .success(.rejected(.notASpeech)))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .rejected(.notASpeech) }

        #expect(viewModel.keyPoints.isEmpty)
    }

    @Test("A short transcript is rejected without the model being called")
    func precheckRejectsWithoutModelCall() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = TranscriptAnalysisViewModel(
            draft: ScriptDraft(
                title: "Oops",
                purpose: .inform,
                transcript: Transcript(original: "hi")
            ),
            availability: FakeAIAvailabilityChecking(.available),
            classifyTranscript: ClassifyTranscriptUseCase(analyzer: analyzer),
            generateKeyPoints: GenerateKeyPointsUseCase(analyzer: analyzer),
            regenerateTranscript: RegenerateTranscriptUseCase(analyzer: analyzer),
            saveScript: SaveScriptUseCase(repository: FakeScriptRepository())
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .rejected(.tooShort) }

        let count = await analyzer.classifyCallCount
        #expect(count == 0)
    }

    @Test("A model failure is a retryable failure, not a rejection")
    func modelFailureIsRetryable() async throws {
        // Blaming the user's content for the app's failure would be both wrong and a dead
        // end — a rejection offers no retry.
        let analyzer = FakeSpeechAnalyzing(classification: .failure(.aiUnavailable))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .failed(.aiUnavailable) }
    }

    @Test("Retry runs the analysis again")
    func retryReRuns() async throws {
        let analyzer = FakeSpeechAnalyzing(classification: .failure(.aiUnavailable))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .failed(.aiUnavailable) }

        await analyzer.setClassification(.success(.usable(rankedPatternIDs: Self.rankedIDs)))
        viewModel.retry()
        try await waitUntil { viewModel.viewState == .loaded }

        #expect(viewModel.selectedPattern?.id == "inform.topical")
    }

    @Test("Retry does nothing when the screen has not failed")
    func retryOnlyAppliesToFailure() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.retry()

        let count = await analyzer.classifyCallCount
        #expect(count == 1)
    }

    // MARK: - Prefetch

    @Test("The other two patterns are prefetched in ranked order after load")
    func prefetchesRemainingPatterns() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await analyzer.keyPointCalls.count == 3 }

        let calls = await analyzer.keyPointCalls
        #expect(calls == Self.rankedIDs)
        _ = viewModel
    }

    @Test("Switching to a prefetched pattern needs no new generation")
    func switchingUsesTheCache() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await analyzer.keyPointCalls.count == 3 }

        let target = try #require(SpeechPatternCatalog.pattern(id: "inform.spatial"))
        viewModel.select(target)
        try await waitUntil { viewModel.selectedPattern?.id == "inform.spatial" }

        let calls = await analyzer.keyPointCalls
        #expect(calls.count == 3, "a cached pattern must not be regenerated")
        #expect(viewModel.keyPoints.map(\.componentID) == target.components.map(\.id))
    }

    @Test("Switching back to an earlier pattern is served from the cache too")
    func switchingBackUsesTheCache() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await analyzer.keyPointCalls.count == 3 }

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        let first = try #require(SpeechPatternCatalog.pattern(id: "inform.topical"))
        viewModel.select(second)
        try await waitUntil { viewModel.selectedPattern?.id == "inform.causeEffect" }
        viewModel.select(first)
        try await waitUntil { viewModel.selectedPattern?.id == "inform.topical" }

        let calls = await analyzer.keyPointCalls
        #expect(calls.count == 3)
    }

    @Test("Re-selecting the pattern already showing does nothing")
    func reselectingIsANoOp() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await analyzer.keyPointCalls.count == 3 }

        let current = try #require(SpeechPatternCatalog.pattern(id: "inform.topical"))
        viewModel.select(current)
        try await Task.sleep(for: .milliseconds(50))

        let calls = await analyzer.keyPointCalls
        #expect(calls.count == 3)
    }

    @Test("A pattern whose prefetch failed is generated on demand when selected")
    func failedPrefetchRetriesOnSelection() async throws {
        // Prefetch failures are swallowed deliberately — it is speculative work the user
        // did not ask for. The cost of that choice is that selection must retry, and this
        // is the test that keeps that true.
        let analyzer = makeAnalyzer()
        await analyzer.setKeyPoints(.failure(.aiGenerationFailed), forPatternID: "inform.spatial")
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await analyzer.keyPointCalls.count == 3 }

        await analyzer.setKeyPoints(.fillAllComponents, forPatternID: "inform.spatial")
        let target = try #require(SpeechPatternCatalog.pattern(id: "inform.spatial"))
        viewModel.select(target)
        try await waitUntil { !viewModel.keyPoints.isEmpty && viewModel.selectedPattern?.id == "inform.spatial" }

        let calls = await analyzer.keyPointCalls
        #expect(calls.filter { $0 == "inform.spatial" }.count == 2)
        #expect(viewModel.keyPoints.allSatisfy { !$0.isAbsent })
    }

    @Test("A failed selection surfaces inline without tearing down the screen")
    func selectionFailureIsInline() async throws {
        let analyzer = makeAnalyzer()
        await analyzer.setKeyPoints(.failure(.aiGenerationFailed), forPatternID: "inform.spatial")
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await analyzer.keyPointCalls.count == 3 }

        let target = try #require(SpeechPatternCatalog.pattern(id: "inform.spatial"))
        viewModel.select(target)
        try await waitUntil { viewModel.actionError != nil }

        #expect(viewModel.viewState == .loaded, "key points already on screen must survive")
    }

    // MARK: - Cancellation

    @Test("cancelAll stops the background prefetch")
    func cancelAllStopsPrefetch() async throws {
        // The specific bug this guards: a prefetch firing an AI call after the user has
        // dismissed the sheet (CLAUDE.md §6).
        let analyzer = makeAnalyzer(delay: .milliseconds(80))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.cancelAll()

        // Long enough that both remaining prefetches would have completed had they run.
        try await Task.sleep(for: .milliseconds(400))

        let calls = await analyzer.keyPointCalls
        #expect(calls.count < 3, "prefetch continued after cancellation: \(calls)")
    }

    @Test("cancelAll stops an in-flight initial analysis")
    func cancelAllStopsInitialAnalysis() async throws {
        let analyzer = makeAnalyzer(delay: .milliseconds(100))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        viewModel.cancelAll()
        try await Task.sleep(for: .milliseconds(400))

        #expect(viewModel.viewState == .analyzing, "a cancelled analysis must not publish")
    }

    @Test("A slow generation for an abandoned pattern does not overwrite the screen")
    func staleGenerationDoesNotOverwrite() async throws {
        // Selection cancels the previous selection task, but a result already in flight
        // must also refuse to publish once it is no longer the selected pattern.
        let analyzer = makeAnalyzer(delay: .milliseconds(60))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        let third = try #require(SpeechPatternCatalog.pattern(id: "inform.spatial"))
        viewModel.select(second)
        viewModel.select(third)

        try await waitUntil { viewModel.selectedPattern?.id == "inform.spatial" && !viewModel.isGeneratingKeyPoints }
        try await Task.sleep(for: .milliseconds(200))

        #expect(viewModel.selectedPattern?.id == "inform.spatial")
        #expect(viewModel.keyPoints.map(\.componentID) == third.components.map(\.id))
    }

    // MARK: - Refined transcript

    @Test("Regenerating produces a refined transcript for the selected pattern")
    func regenerateProducesRefinedTranscript() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        #expect(viewModel.refinedTranscript == nil, "refinement must not run unasked")

        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }

        let calls = await analyzer.refineCalls
        #expect(calls == ["inform.topical"])
        #expect(viewModel.refinedTranscript?.contains("Topical") == true)
    }

    @Test("Regenerating twice for the same pattern reuses the cached result")
    func regenerateIsCached() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }
        viewModel.regenerate()
        try await Task.sleep(for: .milliseconds(50))

        let calls = await analyzer.refineCalls
        #expect(calls.count == 1)
    }

    @Test("Switching patterns clears the refined transcript from the previous one")
    func switchingClearsRefinedTranscript() async throws {
        // Leaving one pattern's rewritten text under another pattern's key points would be
        // quietly, confusingly wrong.
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        viewModel.select(second)
        try await waitUntil { viewModel.selectedPattern?.id == "inform.causeEffect" }

        #expect(viewModel.refinedTranscript == nil)
    }

    @Test("Switching back restores that pattern's cached refined transcript")
    func switchingBackRestoresRefinedTranscript() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        let first = try #require(SpeechPatternCatalog.pattern(id: "inform.topical"))
        viewModel.select(second)
        try await waitUntil { viewModel.refinedTranscript == nil }
        viewModel.select(first)
        try await waitUntil { viewModel.refinedTranscript != nil }

        let calls = await analyzer.refineCalls
        #expect(calls.count == 1, "the cached refinement must not be regenerated")
    }

    @Test("A failed refinement surfaces inline and keeps the screen loaded")
    func refinementFailureIsInline() async throws {
        let analyzer = makeAnalyzer()
        await analyzer.setRefined(.failure(.aiGenerationFailed))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.actionError != nil }

        #expect(viewModel.viewState == .loaded)
        #expect(viewModel.refinedTranscript == nil)
    }

    @Test("Blank model output is reported rather than stored as an empty transcript")
    func blankRefinementIsAFailure() async throws {
        let analyzer = makeAnalyzer()
        await analyzer.setRefined(.success("   "))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.actionError != nil }

        #expect(viewModel.refinedTranscript == nil)
    }

    // MARK: - Saving

    @Test("Saving persists the analyzed script")
    func savePersists() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.save()
        try await waitUntil { await repository.saveCount == 1 }

        let scripts = await repository.scripts
        let saved = try #require(scripts.first)
        #expect(saved.title == "Why remote work stuck")
        #expect(saved.selectedPatternID == "inform.topical")
        #expect(saved.suggestedPatternIDs == Self.rankedIDs)
        #expect(!saved.keyPoints.isEmpty)
    }

    @Test("Saving twice updates the same script rather than inserting a second")
    func saveTwiceUpdates() async throws {
        // The draft has to learn its assigned id after the first save, or the second one
        // silently duplicates it.
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.save()
        try await waitUntil { await repository.saveCount == 1 }
        viewModel.save()
        try await waitUntil { await repository.saveCount == 2 }

        let scripts = await repository.scripts
        #expect(scripts.count == 1)
    }

    @Test("A save failure surfaces inline")
    func saveFailureIsInline() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository(throwing: .persistenceFailed)
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.save()
        try await waitUntil { viewModel.actionError != nil }

        #expect(viewModel.viewState == .loaded)
    }

    @Test("A successful analysis persists the script without the user asking")
    func analysisAutoSaves() async throws {
        // From `.loaded` onwards the user can leave by ✕, by swipe, or by the app being
        // killed — none of which we get to intercept reliably. Persisting the moment the
        // analysis is real is what makes leaving survivable.
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        // Note: no `viewModel.save()` here — that is the whole point of the test.
        try await waitUntil { await repository.saveCount == 1 }

        let scripts = await repository.scripts
        let saved = try #require(scripts.first)
        #expect(saved.title == "Why remote work stuck")
        #expect(saved.selectedPatternID == "inform.topical")
        #expect(!saved.keyPoints.isEmpty)
    }

    @Test("Saving after the automatic save updates that script rather than inserting a second")
    func explicitSaveUpdatesTheAutoSavedScript() async throws {
        // The automatic save carries the assigned id back onto the draft; without that,
        // tapping ✓ would leave the user with two copies of the same speech.
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        let autoSavedID = try #require(viewModel.draft.existingScriptID)
        viewModel.save()
        try await waitUntil { await repository.saveCount == 2 }

        let scripts = await repository.scripts
        #expect(scripts.count == 1, "the explicit save inserted a duplicate: \(scripts.map(\.id))")
        #expect(scripts.first?.id == autoSavedID)
        #expect(viewModel.draft.existingScriptID == autoSavedID)
    }

    @Test("hasUnsavedChanges is clear on load, set by a pattern switch, and cleared again by saving")
    func hasUnsavedChangesTracksTheDraft() async throws {
        // This is what lets ✕ tell "nothing to lose" apart from "you have changes".
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }
        #expect(!viewModel.hasUnsavedChanges, "the automatic save leaves nothing outstanding")

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        viewModel.select(second)
        try await waitUntil { viewModel.hasUnsavedChanges }

        viewModel.save()
        try await waitUntil { await repository.saveCount == 2 }
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("cancelAll does not stop an in-flight save from completing")
    func cancelAllLetsTheSaveFinish() async throws {
        // Generations are speculative and safe to abandon; a save is the one operation
        // whose whole purpose is to outlive the screen. Cancelling it on dismissal would
        // re-create exactly the data loss the automatic save exists to prevent.
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository(after: .milliseconds(150))
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        // `.loaded` is published in the same turn the automatic save starts, so the save is
        // still sitting in the repository's delay right now.
        #expect(viewModel.isSaving, "the save should still be in flight for this test to mean anything")
        let beforeCancel = await repository.saveCount
        #expect(beforeCancel == 0)

        viewModel.cancelAll()
        try await waitUntil { await repository.saveCount == 1 }

        let scripts = await repository.scripts
        #expect(scripts.count == 1)
        #expect(viewModel.draft.existingScriptID != nil)
    }

    @Test("A superseded key-point generation does not clear the spinner for the one that replaced it")
    func supersededGenerationLeavesTheSpinnerAlone() async throws {
        // Cancelling a Task does not unwind it immediately: the loser resumes from its
        // cancelled await and runs its `defer` *after* the winner has already raised the
        // flag. Without a generation tag the loser turns the winner's spinner off, and the
        // user watches an idle screen while work is actually running.
        let analyzer = makeAnalyzer(delay: .milliseconds(150))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        let third = try #require(SpeechPatternCatalog.pattern(id: "inform.spatial"))
        viewModel.select(second)
        viewModel.select(third)

        try await waitUntil { viewModel.selectedPattern?.id == "inform.spatial" }
        #expect(
            viewModel.isGeneratingKeyPoints,
            "the cancelled selection cleared the spinner belonging to the run that replaced it"
        )

        try await waitUntil { !viewModel.isGeneratingKeyPoints }
        #expect(viewModel.keyPoints.map(\.componentID) == third.components.map(\.id))
    }

    @Test("Dismissing an inline error clears it")
    func dismissClearsActionError() async throws {
        let analyzer = makeAnalyzer()
        await analyzer.setRefined(.failure(.aiGenerationFailed))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.actionError != nil }
        viewModel.dismissActionError()

        #expect(viewModel.actionError == nil)
    }

}
