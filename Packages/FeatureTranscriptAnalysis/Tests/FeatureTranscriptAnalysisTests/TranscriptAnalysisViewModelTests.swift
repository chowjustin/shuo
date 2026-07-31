//
//  TranscriptAnalysisViewModelTests.swift
//  FeatureTranscriptAnalysisTests
//
//  Created by Justin Chow on 13/07/26.
//

@testable import FeatureTranscriptAnalysis
import Foundation
import ShuoCore
import ShuoTestSupport
import Testing

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
        makeViewModel(draft: makeDraft(), analyzer: analyzer, repository: repository,
                      availability: availability)
    }

    private func makeViewModel(
        draft: ScriptDraft,
        analyzer: FakeSpeechAnalyzing,
        repository: FakeScriptRepository = FakeScriptRepository(),
        availability: any AIAvailabilityChecking = FakeAIAvailabilityChecking(.available)
    ) -> TranscriptAnalysisViewModel {
        let viewModel = TranscriptAnalysisViewModel(
            draft: draft,
            availability: availability,
            classifyTranscript: ClassifyTranscriptUseCase(analyzer: analyzer),
            generateKeyPoints: GenerateKeyPointsUseCase(analyzer: analyzer),
            regenerateTranscript: RegenerateTranscriptUseCase(analyzer: analyzer),
            saveScript: SaveScriptUseCase(repository: repository),
            nextUntitledTitle: NextUntitledScriptTitleUseCase(repository: repository)
        )
        viewModel.availabilityPollInterval = .milliseconds(10)
        return viewModel
    }

    /// A reopened draft carrying a complete, saved per-pattern analysis for the top two inform patterns.
    private func makeReopenedDraft() -> ScriptDraft {
        func savedKeyPoints(_ patternID: String) -> [KeyPoint] {
            guard let pattern = SpeechPatternCatalog.pattern(id: patternID) else { return [] }
            return pattern.components.map {
                KeyPoint(componentID: $0.id, componentName: $0.name,
                         text: "Saved \($0.name).", orderIndex: $0.order)
            }
        }
        return ScriptDraft(
            existingScriptID: UUID(),
            title: "Reopened script",
            purpose: .inform,
            transcript: Transcript(original: Self.transcript, refined: "Saved topical refinement."),
            suggestedPatternIDs: Self.rankedIDs,
            selectedPatternID: "inform.topical",
            keyPoints: savedKeyPoints("inform.topical"),
            keyPointsByPattern: [
                "inform.topical": savedKeyPoints("inform.topical"),
                "inform.causeEffect": savedKeyPoints("inform.causeEffect"),
            ],
            refinedByPattern: [
                "inform.topical": "Saved topical refinement.",
                "inform.causeEffect": "Saved cause-effect refinement.",
            ]
        )
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

    /// Polls until `condition` holds, so tests wait on observable state rather than on a fixed sleep.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
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
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.viewState == .waitingForModel)
        let count = await analyzer.classifyCallCount
        #expect(count == 0, "classification ran before the model was ready")
    }

    @Test("Analysis continues on its own once the model becomes ready")
    func modelBecomesReady() async throws {
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
        let analyzer = makeAnalyzer()
        let availability = FakeAIAvailabilityChecking(.modelNotReady)
        let viewModel = makeViewModel(analyzer: analyzer, availability: availability)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .waitingForModel }
        viewModel.cancelAll()

        try await Task.sleep(for: .milliseconds(60))
        let afterCancel = await availability.callCount
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

        viewModel.title = ""
        #expect(viewModel.title.isEmpty)

        viewModel.commitTitle()

        #expect(viewModel.title == UntitledScriptTitle.first)
        #expect(viewModel.draft.title == UntitledScriptTitle.first)
    }

    @Test("Clearing the title keeps the number the script is already saved under")
    func clearedTitleKeepsItsOwnNumber() async throws {
        // The draft arrived from Input Script already named `Untitled Script 2`, and the
        // automatic save (§16) has written it under that name. Numbering afresh here would
        // find that record and hand back 3 — renaming the user's script for clearing a field.
        var draft = makeDraft()
        draft.title = UntitledScriptTitle.named(2)
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(draft: draft, analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        viewModel.title = ""
        viewModel.commitTitle()

        #expect(viewModel.title == UntitledScriptTitle.named(2))
    }

    @Test("Clearing the title on a named script numbers past the untitled scripts stored")
    func clearedTitleOnNamedScriptTakesTheNextNumber() async throws {
        let saved = Script(
            title: UntitledScriptTitle.named(3),
            purpose: .inform,
            transcript: Transcript(original: Self.transcript),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository(scripts: [saved])
        // `makeDraft` is titled "Why remote work stuck" — a name of its own, so clearing it
        // has to reach for a number that is actually free.
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        viewModel.title = ""
        viewModel.commitTitle()

        #expect(viewModel.title == UntitledScriptTitle.named(4))
    }

    @Test("A whitespace-only title is treated as empty, not saved as spaces")
    func whitespaceOnlyTitleFallsBack() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        viewModel.title = "   \n "
        viewModel.commitTitle()

        #expect(viewModel.title == UntitledScriptTitle.first)
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

        viewModel.title = ""
        viewModel.save()
        try await waitUntil { await repository.saveCount == 2 }

        let scripts = await repository.scripts
        #expect(scripts.count == 1)
        #expect(scripts.first?.title == UntitledScriptTitle.first)
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
            saveScript: SaveScriptUseCase(repository: FakeScriptRepository()),
            nextUntitledTitle: NextUntitledScriptTitleUseCase(repository: FakeScriptRepository())
        )

        viewModel.start()
        try await waitUntil { viewModel.viewState == .rejected(.tooFewWords) }

        let count = await analyzer.classifyCallCount
        #expect(count == 0)
    }

    @Test("A model failure is a retryable failure, not a rejection")
    func modelFailureIsRetryable() async throws {
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
        let analyzer = makeAnalyzer(delay: .milliseconds(80))
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.cancelAll()

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

    @Test("The refined transcript is never generated on load, for any pattern")
    func loadDoesNotRefine() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await Task.sleep(for: .milliseconds(80))

        #expect(viewModel.refinedTranscript == nil, "refinement must not run unasked")
        #expect(await analyzer.refineCalls.isEmpty)
    }

    @Test("Regenerating produces a refined transcript for the selected pattern")
    func regenerateProducesRefinedTranscript() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }

        let calls = await analyzer.refineCalls
        #expect(calls == ["inform.topical"], "exactly one refinement, for the pattern asked")
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

    @Test("Backing out of a forced refinement returns to the analysis, not out of it")
    func cancellingAForcedRefinementReturnsToTheAnalysis() async throws {
        // ‹ during "Refining script…" belongs to that state, not to the screen behind it.
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        await analyzer.setDelay(.seconds(5))
        viewModel.forceRegenerate()
        #expect(viewModel.isForceRegenerating)

        viewModel.cancelForceRegeneration()

        #expect(!viewModel.isForceRegenerating)
        #expect(!viewModel.isRegeneratingTranscript)
        #expect(viewModel.viewState == .loaded)
    }

    @Test("Backing out of a forced refinement puts the previous one back")
    func cancellingAForcedRefinementRestoresTheReplacedText() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }
        let original = try #require(viewModel.refinedTranscript)

        await analyzer.setDelay(.seconds(5))
        viewModel.forceRegenerate()
        #expect(viewModel.refinedTranscript == nil, "↺ clears it before regenerating")

        viewModel.cancelForceRegeneration()

        #expect(viewModel.refinedTranscript == original)
        #expect(viewModel.editableRefinedText == original)
    }

    @Test("A refinement backed out of never lands on the screen afterwards")
    func cancelledForcedRefinementDoesNotArriveLate() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }
        let original = try #require(viewModel.refinedTranscript)

        await analyzer.setDelay(.milliseconds(50))
        viewModel.forceRegenerate()
        viewModel.cancelForceRegeneration()
        try await Task.sleep(for: .milliseconds(250))

        #expect(viewModel.refinedTranscript == original)
        #expect(!viewModel.isForceRegenerating)
        #expect(!viewModel.isRegeneratingTranscript)
    }

    @Test("Backing out when nothing is being force-refined is a no-op")
    func cancellingAForcedRefinementThatIsNotRunningDoesNothing() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }
        let original = try #require(viewModel.refinedTranscript)

        viewModel.cancelForceRegeneration()

        #expect(viewModel.refinedTranscript == original)
        #expect(viewModel.viewState == .loaded)
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
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount == 1 }

        let scripts = await repository.scripts
        let saved = try #require(scripts.first)
        #expect(saved.title == "Why remote work stuck")
        #expect(saved.selectedPatternID == "inform.topical")
        #expect(!saved.keyPoints.isEmpty)
    }

    @Test("Saving after the automatic save updates that script rather than inserting a second")
    func explicitSaveUpdatesTheAutoSavedScript() async throws {
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
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository(after: .milliseconds(150))
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

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

    // MARK: - Reopening a saved script (no reprocessing)

    @Test("Reopening a saved script restores it without any AI call")
    func reopenMakesNoAICalls() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(draft: makeReopenedDraft(), analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await Task.sleep(for: .milliseconds(150))

        #expect(await analyzer.classifyCallCount == 0)
        #expect(await analyzer.keyPointCalls.isEmpty)
        #expect(await analyzer.refineCalls.isEmpty)
        #expect(viewModel.selectedPattern?.id == "inform.topical")
        #expect(viewModel.refinedTranscript == "Saved topical refinement.")
    }

    @Test("Switching patterns on a reopened script is served entirely from saved data")
    func reopenSwitchUsesSavedDataOnly() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(draft: makeReopenedDraft(), analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }

        let causeEffect = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        viewModel.select(causeEffect)
        try await waitUntil { viewModel.selectedPattern?.id == "inform.causeEffect" }

        #expect(viewModel.keyPoints.map(\.componentID) == causeEffect.components.map(\.id))
        #expect(viewModel.keyPoints.allSatisfy { $0.text.hasPrefix("Saved ") })
        #expect(viewModel.refinedTranscript == "Saved cause-effect refinement.")
        #expect(await analyzer.keyPointCalls.isEmpty)
        #expect(await analyzer.refineCalls.isEmpty)
    }

    @Test("A reopened script does not run the background prefetch")
    func reopenDoesNotPrefetch() async throws {
        let analyzer = makeAnalyzer(delay: .milliseconds(20))
        let viewModel = makeViewModel(draft: makeReopenedDraft(), analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await Task.sleep(for: .milliseconds(150))

        #expect(await analyzer.keyPointCalls.isEmpty, "prefetch regenerated key points on reopen")
    }

    // MARK: - Per-pattern persistence

    @Test("A new script persists every suggested pattern's key points, not just the selected one")
    func savePersistsAllPatternsKeyPoints() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)
        viewModel.autoSaveDebounce = .milliseconds(20)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        try await waitUntil { await repository.saveCount >= 2 }

        let scripts = await repository.scripts
        let saved = try #require(scripts.first)
        #expect(Set(saved.keyPointsByPattern.keys) == Set(Self.rankedIDs),
                "all three patterns' key points must be persisted: \(saved.keyPointsByPattern.keys)")
    }

    @Test("A user-generated refined transcript is persisted per pattern")
    func savePersistsRefinedPerPattern() async throws {
        let analyzer = makeAnalyzer()
        let repository = FakeScriptRepository()
        let viewModel = makeViewModel(analyzer: analyzer, repository: repository)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { viewModel.refinedTranscript != nil }
        viewModel.save()
        try await waitUntil { await repository.saveCount >= 1 }

        let scripts = await repository.scripts
        let saved = try #require(scripts.first)
        #expect(saved.refinedByPattern["inform.topical"] == saved.transcript.refined)
    }

    // MARK: - On-demand refined transcript

    @Test("Switching to a new pattern does not auto-generate its refined transcript")
    func switchDoesNotAutoRegenerate() async throws {
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        viewModel.regenerate()
        try await waitUntil { await analyzer.refineCalls == ["inform.topical"] }

        let second = try #require(SpeechPatternCatalog.pattern(id: "inform.causeEffect"))
        viewModel.select(second)
        try await waitUntil { viewModel.selectedPattern?.id == "inform.causeEffect" }
        try await Task.sleep(for: .milliseconds(80))

        #expect(await analyzer.refineCalls == ["inform.topical"],
                "switching a pattern must not fire a refinement on its own")
        #expect(viewModel.refinedTranscript == nil, "the new pattern has no refinement until asked")
    }

    @Test("hasUnfulfilledKeyPoints reflects whether any key point is still absent")
    func unfulfilledKeyPointsFlag() async throws {
        let analyzer = makeAnalyzer()
        await analyzer.setKeyPoints(.fillAllComponents, forPatternID: "inform.topical")
        let viewModel = makeViewModel(analyzer: analyzer)

        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        #expect(!viewModel.hasUnfulfilledKeyPoints, "a fully filled set has nothing unaddressed")

        let first = try #require(viewModel.keyPoints.first)
        viewModel.updateKeyPoint(id: first.id, text: KeyPoint.absentText)
        #expect(viewModel.hasUnfulfilledKeyPoints)
    }

    // MARK: - Re-entering a loaded screen

    @Test("Returning to a loaded analysis does not regenerate it")
    func reenteringALoadedScreenDoesNotRegenerate() async throws {
        // ‹ back to Input Script and ✓ forward again puts this same view model behind a
        // fresh view, whose `.task` calls `start()` again — and `cancelAll()` on the way
        // out has already cleared the task handle that used to be the only guard. Without
        // the `.loaded` check, returning reruns the whole on-device pipeline over an
        // analysis sitting in memory, complete, with the user's edits in it.
        let analyzer = makeAnalyzer()
        let viewModel = makeViewModel(analyzer: analyzer)
        viewModel.start()
        try await waitUntil { viewModel.viewState == .loaded }
        let classifyCallsAfterFirstLoad = await analyzer.classifyCallCount
        let keyPointsBefore = viewModel.keyPoints

        viewModel.cancelAll()
        viewModel.start()

        #expect(viewModel.viewState == .loaded)
        #expect(await analyzer.classifyCallCount == classifyCallsAfterFirstLoad)
        #expect(viewModel.keyPoints == keyPointsBefore)
    }
}
