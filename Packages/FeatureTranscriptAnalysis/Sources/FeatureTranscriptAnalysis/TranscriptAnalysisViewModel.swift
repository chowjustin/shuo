//
//  TranscriptAnalysisViewModel.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore

/// Drives the transcript analysis screen.
@Observable
@MainActor
public final class TranscriptAnalysisViewModel {

    // MARK: - Observable state

    public private(set) var viewState: TranscriptAnalysisViewState = .analyzing
    /// The working script.
    public private(set) var draft: ScriptDraft
    /// The up-to-3 pattern carousel.
    public let carousel: PatternCarouselViewModel
    /// Key points for the selected pattern — always one per component, in order.
    public private(set) var keyPoints: [KeyPoint] = []
    /// True while key points for a newly selected pattern are being generated.
    public private(set) var isGeneratingKeyPoints = false
    /// True while the refined transcript is being generated.
    public private(set) var isRegeneratingTranscript = false
    /// True only when the user explicitly pressed ↺ to force a re-generation.
    public private(set) var isForceRegenerating = false
    /// A failure from selecting a pattern or regenerating, shown inline.
    public private(set) var actionError: ShuoError?
    public private(set) var isSaving = false
    /// True when the draft has changed since it was last persisted.
    public private(set) var hasUnsavedChanges = false

    /// The refined transcript text as shown in the editing TextField.
    public var editableRefinedText: String = "" {
        didSet {
            guard editableRefinedText != draft.transcript.refined else { return }
            draft.transcript.refined = editableRefinedText.isEmpty ? nil : editableRefinedText
            if let patternID = draft.selectedPatternID {
                refinedCache[patternID] = editableRefinedText.isEmpty ? nil : editableRefinedText
            }
            hasUnsavedChanges = true
            scheduleSave()
        }
    }

    // MARK: - Dependencies

    private let availability: any AIAvailabilityChecking
    private let classifyTranscript: ClassifyTranscriptUseCase
    private let generateKeyPoints: GenerateKeyPointsUseCase
    private let regenerateTranscript: RegenerateTranscriptUseCase
    private let saveScript: SaveScriptUseCase
    private let highlighter = TranscriptHighlighter()

    /// How long to wait between availability checks while the model is warming up.
    var availabilityPollInterval: Duration = .seconds(2)

    /// How long after the last change to wait before writing it.
    var autoSaveDebounce: Duration = .seconds(1)

    // MARK: - Caches

    private var keyPointCache: [SpeechPattern.ID: [KeyPoint]] = [:]
    private var refinedCache: [SpeechPattern.ID: String] = [:]

    // MARK: - In-flight work

    private var analysisTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var regenerationTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var autoSaveTask: Task<Void, Never>?

    /// Monotonic tags identifying the newest key-point / refinement run.
    private var keyPointsGeneration = 0
    private var regenerationGeneration = 0

    public init(
        draft: ScriptDraft,
        availability: any AIAvailabilityChecking,
        classifyTranscript: ClassifyTranscriptUseCase,
        generateKeyPoints: GenerateKeyPointsUseCase,
        regenerateTranscript: RegenerateTranscriptUseCase,
        saveScript: SaveScriptUseCase
    ) {
        self.draft = draft
        self.availability = availability
        self.classifyTranscript = classifyTranscript
        self.generateKeyPoints = generateKeyPoints
        self.regenerateTranscript = regenerateTranscript
        self.saveScript = saveScript
        self.carousel = PatternCarouselViewModel()
    }

    // MARK: - Derived

    /// The fallback name for a script the user never named.
    static let untitledTitle = "Untitled Script"

    /// The script's title, renameable from the analysis screen.
    public var title: String {
        get { draft.title }
        set {
            guard newValue != draft.title else { return }
            draft.title = newValue
            hasUnsavedChanges = true
        }
    }

    /// Adopts a title the user changed on Input Script before stepping forward again.
    ///
    /// Returning to an analysis that is already on screen skips the whole pipeline, so the
    /// rename made on the way back would otherwise be the one edit that silently didn't
    /// take. A no-op when the title is unchanged, so re-entering cannot mark a clean draft
    /// dirty on its own.
    public func applyTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != draft.title else { return }
        title = trimmed
        scheduleSave()
    }

    /// Settles the title once the user is done editing it: trims surrounding whitespace, and falls back to `untitledTitle` if that leaves nothing.
    public func commitTitle() {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? Self.untitledTitle : trimmed
        if hasUnsavedChanges { scheduleSave() }
    }
    public var originalTranscript: String { draft.transcript.original }
    /// The refined transcript for the selected pattern, or nil if it has not been generated yet.
    public var refinedTranscript: String? { draft.transcript.refined }
    public var selectedPattern: SpeechPattern? { draft.selectedPattern }
    /// True when the user has something to regenerate against.
    public var canRegenerateTranscript: Bool {
        selectedPattern != nil && !isRegeneratingTranscript
    }

    /// True when at least one key point for the selected pattern is still unaddressed.
    public var hasUnfulfilledKeyPoints: Bool {
        keyPoints.contains { $0.isAbsent }
    }

    /// True once a refined transcript exists for the selected pattern.
    public var hasRefinedTranscript: Bool {
        !(draft.transcript.refined ?? "").isEmpty
    }

    /// Character-offset ranges in the refined transcript that convey the current key points, for the UI to highlight.
    public var refinedHighlightRanges: [Range<Int>] {
        guard !editableRefinedText.isEmpty else { return [] }
        return highlighter.highlightRanges(in: editableRefinedText, keyPoints: keyPoints)
    }

    // MARK: - Lifecycle

    /// Starts the screen. If the draft already has saved analysis data (reopened script),
    /// loads directly from it; otherwise runs the AI pipeline.
    public func start() {
        // `.loaded` is checked as well as the task handle, because this screen is now
        // re-entered rather than rebuilt: ‹ back to Input Script and ✓ forward again puts
        // the same view model behind a fresh view, and `cancelAll()` on the way out
        // already cleared `analysisTask`. Without this, returning would regenerate an
        // analysis that is sitting in memory, complete, with the user's edits in it.
        guard analysisTask == nil, viewState != .loaded else { return }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            if hasReopenableAnalysis {
                await loadReopenedScript()
            } else {
                await runInitialAnalysis()
            }
        }
    }

    /// True when the draft was reopened *and* carries a complete saved analysis, so the screen can be restored verbatim without a single AI call.
    private var hasReopenableAnalysis: Bool {
        draft.isReopenedScript
            && !draft.suggestedPatternIDs.isEmpty
            && draft.selectedPatternID != nil
            && !draft.keyPoints.isEmpty
    }

    /// Cancels every in-flight *generation*.
    public func cancelAll() {
        analysisTask?.cancel()
        selectionTask?.cancel()
        prefetchTask?.cancel()
        regenerationTask?.cancel()
        autoSaveTask?.cancel()
        analysisTask = nil
        selectionTask = nil
        prefetchTask = nil
        regenerationTask = nil
        autoSaveTask = nil
    }

    /// Retries after a failed initial analysis.
    public func retry() {
        guard case .failed = viewState else { return }
        cancelAll()
        viewState = .analyzing
        start()
    }

    // MARK: - Initial analysis

    /// Restores the screen from previously saved analysis — **no AI call, ever**.
    private func loadReopenedScript() async {
        guard !Task.isCancelled else { return }
        let patterns = draft.suggestedPatterns
        guard let selectedPatternID = draft.selectedPatternID,
              let selectedPattern = draft.selectedPattern,
              !patterns.isEmpty else {
            await runInitialAnalysis()
            return
        }

        keyPointCache = draft.keyPointsByPattern
        refinedCache = draft.refinedByPattern
        if keyPointCache[selectedPatternID] == nil, !draft.keyPoints.isEmpty {
            keyPointCache[selectedPatternID] = draft.keyPoints
        }
        if refinedCache[selectedPatternID] == nil,
           let refined = draft.transcript.refined, !refined.isEmpty {
            refinedCache[selectedPatternID] = refined
        }

        carousel.update(patterns: patterns)
        carousel.select(selectedPattern)

        keyPoints = keyPointCache[selectedPatternID] ?? draft.keyPoints
        draft.keyPoints = keyPoints

        if let refined = refinedCache[selectedPatternID], !refined.isEmpty {
            draft.transcript.refined = refined
            editableRefinedText = refined
            updateSuggestionsFromRefined(refined)
        } else {
            draft.transcript.refined = nil
            editableRefinedText = ""
        }

        viewState = .loaded
        hasUnsavedChanges = false

        carousel.onSelect = { [weak self] pattern in
            self?.select(pattern)
        }
    }

    /// Runs the full AI pipeline for a *new* script.
    private func runInitialAnalysis() async {
        guard await waitForModel() else { return }

        do {
            let patterns = try await classifyTranscript(
                transcript: draft.transcript,
                purpose: draft.purpose
            )
            guard !Task.isCancelled else { return }

            draft.suggestedPatternIDs = patterns.map(\.id)
            carousel.update(patterns: patterns)

            guard let top = patterns.first else {
                viewState = .failed(.aiGenerationFailed)
                return
            }

            carousel.select(top)
            try await applyPattern(top)
            guard !Task.isCancelled else { return }

            viewState = .loaded
            save()
            carousel.onSelect = { [weak self] pattern in
                self?.select(pattern)
            }
            startPrefetch(excluding: top.id, from: patterns)
        } catch let error as ShuoError {
            guard !Task.isCancelled else { return }
            viewState = Self.viewState(for: error)
        } catch {
            guard !Task.isCancelled else { return }
            viewState = .failed(.aiGenerationFailed)
        }
    }
    
    /// Waits until on-device generation is possible, returning false if it never will be.
    private func waitForModel() async -> Bool {
        while true {
            let status = await availability.availability()
            guard !Task.isCancelled else { return false }

            switch status {
            case .available:
                if viewState == .waitingForModel { viewState = .analyzing }
                return true

            case .modelNotReady:
                viewState = .waitingForModel
                do {
                    try await Task.sleep(for: availabilityPollInterval)
                } catch {
                    return false
                }

            case .appleIntelligenceNotEnabled, .deviceNotEligible:
                viewState = .unavailable(status)
                return false
            }
        }
    }

    private static func viewState(for error: ShuoError) -> TranscriptAnalysisViewState {
        if case .transcriptNotUsable(let reason) = error {
            return .rejected(reason)
        }
        return .failed(error)
    }

    // MARK: - Pattern selection

    /// Switches to `pattern`, generating its key points if they aren't cached.
    public func select(_ pattern: SpeechPattern) {
        guard pattern.id != draft.selectedPatternID || keyPoints.isEmpty else { return }

        selectionTask?.cancel()
        prefetchTask?.cancel()
        actionError = nil

        selectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await applyPattern(pattern)
            } catch is CancellationError {
                return
            } catch let error as ShuoError {
                guard !Task.isCancelled else { return }
                actionError = error
            } catch {
                guard !Task.isCancelled else { return }
                actionError = .aiGenerationFailed
            }
            guard !Task.isCancelled else { return }
            isForceRegenerating = false
            scheduleSave()
            resumePrefetch()
        }
    }

    /// Points the draft at `pattern` and puts its key points on screen, generating them if they are not already cached.
    private func applyPattern(_ pattern: SpeechPattern) async throws {
        draft.selectedPatternID = pattern.id
        draft.transcript.refined = refinedCache[pattern.id]
        editableRefinedText = refinedCache[pattern.id] ?? ""
        hasUnsavedChanges = true

        if let cached = keyPointCache[pattern.id] {
            keyPoints = cached
            draft.keyPoints = cached
            return
        }

        keyPointsGeneration &+= 1
        let generation = keyPointsGeneration
        isGeneratingKeyPoints = true
        defer { if generation == keyPointsGeneration { isGeneratingKeyPoints = false } }

        let generated = try await generateKeyPoints(
            transcript: draft.transcript,
            pattern: pattern
        )
        try Task.checkCancellation()

        keyPointCache[pattern.id] = generated
        guard draft.selectedPatternID == pattern.id else { return }
        keyPoints = generated
        draft.keyPoints = generated
    }

    // MARK: - Prefetch

    /// Generates key points for the non-selected patterns, one at a time, in the background.
    private func startPrefetch(excluding selectedID: SpeechPattern.ID, from patterns: [SpeechPattern]) {
        let pending = patterns.filter { $0.id != selectedID && keyPointCache[$0.id] == nil }
        guard !pending.isEmpty else { return }

        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            for pattern in pending {
                guard let self, !Task.isCancelled else { return }
                guard let generated = try? await generateKeyPoints(
                    transcript: draft.transcript,
                    pattern: pattern
                ) else { continue }
                guard !Task.isCancelled else { return }
                keyPointCache[pattern.id] = generated
            }
            guard let self, !Task.isCancelled else { return }
            scheduleSave()
        }
    }

    /// Restarts prefetching for whatever is still uncached after a selection interrupted it.
    private func resumePrefetch() {
        guard !draft.isReopenedScript, let selectedID = draft.selectedPatternID else { return }
        startPrefetch(excluding: selectedID, from: carousel.patterns)
    }

    // MARK: - Refined transcript

    /// Generates the refined transcript for the selected pattern, using the cache when available.
    public func regenerate() {
        guard let pattern = selectedPattern else { return }

        regenerationTask?.cancel()
        actionError = nil

        if let cached = refinedCache[pattern.id] {
            draft.transcript.refined = cached
            editableRefinedText = cached
            hasUnsavedChanges = true
            return
        }

        regenerationGeneration &+= 1
        let generation = regenerationGeneration
        let snapshotKeyPoints = keyPoints
        isRegeneratingTranscript = true
        regenerationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == regenerationGeneration {
                    isRegeneratingTranscript = false
                    isForceRegenerating = false
                }
            }
            do {
                let refined = try await regenerateTranscript(
                    transcript: draft.transcript,
                    pattern: pattern,
                    keyPoints: snapshotKeyPoints
                )
                try Task.checkCancellation()
                refinedCache[pattern.id] = refined
                guard draft.selectedPatternID == pattern.id else { return }
                draft.transcript.refined = refined
                editableRefinedText = refined
                updateSuggestionsFromRefined(refined)
                hasUnsavedChanges = true
                save()
            } catch is CancellationError {
                return
            } catch let error as ShuoError {
                guard !Task.isCancelled else { return }
                actionError = error
            } catch {
                guard !Task.isCancelled else { return }
                actionError = .aiGenerationFailed
            }
        }
    }

    // MARK: - Saving

    /// Schedules a save 1.5 s after the last change, cancelling any pending auto-save.
    private func scheduleSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: autoSaveDebounce)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Copies the per-pattern key-point and refinement caches onto the draft so a save persists them.
    private func syncPerPatternCachesIntoDraft() {
        draft.keyPointsByPattern = keyPointCache
        draft.refinedByPattern = refinedCache
    }

    /// Persists the draft. Updates the reopened script when there is one, inserts otherwise.
    public func save(onSaved: (@MainActor (Script) -> Void)? = nil) {
        guard !isSaving else { return }
        commitTitle()
        syncPerPatternCachesIntoDraft()

        isSaving = true
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { isSaving = false }
            do {
                let script = try await saveScript(draft)
                try Task.checkCancellation()
                draft.existingScriptID = script.id
                hasUnsavedChanges = false
                onSaved?(script)
            } catch is CancellationError {
                return
            } catch let error as ShuoError {
                guard !Task.isCancelled else { return }
                actionError = error
            } catch {
                guard !Task.isCancelled else { return }
                actionError = .persistenceFailed
            }
        }
    }

    /// Discards any manual edit and re-generates the refined transcript with AI.
    public func forceRegenerate() {
        guard let patternID = draft.selectedPatternID else { return }
        refinedCache.removeValue(forKey: patternID)
        draft.transcript.refined = nil
        editableRefinedText = ""
        isForceRegenerating = true
        regenerate()
    }

    /// Updates the text of a single key point after the user edits it in the card.
    public func updateKeyPoint(id: KeyPoint.ID, text: String) {
        guard let idx = keyPoints.firstIndex(where: { $0.id == id }),
              keyPoints[idx].text != text else { return }
        keyPoints[idx].text = text
        draft.keyPoints = keyPoints
        if let patternID = draft.selectedPatternID {
            keyPointCache[patternID] = keyPoints
        }
        hasUnsavedChanges = true
        scheduleSave()
    }



    /// Clears an inline error after the user dismisses it.
    public func dismissActionError() {
        actionError = nil
    }

    /// Replaces suggestions for absent key points with relevant sentences from the refined transcript.
    private func updateSuggestionsFromRefined(_ refined: String) {
        let sentences = refined
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 4 }

        guard !sentences.isEmpty else { return }
        let sentenceCount = sentences.count

        keyPoints = keyPoints.map { keyPoint in
            guard keyPoint.isAbsent else { return keyPoint }

            let keywords = keyPoint.componentName
                .components(separatedBy: CharacterSet(charactersIn: " –-/"))
                .map { $0.lowercased() }
                .filter { $0.count > 3 }

            let componentFraction = keyPoints.count > 1
                ? Double(keyPoint.orderIndex) / Double(keyPoints.count - 1)
                : 0.5

            let best = sentences.enumerated().max { a, b in
                let aScore = keywords.filter { a.element.lowercased().contains($0) }.count
                let bScore = keywords.filter { b.element.lowercased().contains($0) }.count
                guard aScore == bScore else { return aScore < bScore }
                let aProximity = sentenceCount > 1
                    ? abs(Double(a.offset) / Double(sentenceCount - 1) - componentFraction)
                    : 0.0
                let bProximity = sentenceCount > 1
                    ? abs(Double(b.offset) / Double(sentenceCount - 1) - componentFraction)
                    : 0.0
                return aProximity > bProximity
            }

            var updated = keyPoint
            if let (_, sentence) = best, !sentence.isEmpty {
                updated.suggestion = sentence
            }
            return updated
        }
    }
}
