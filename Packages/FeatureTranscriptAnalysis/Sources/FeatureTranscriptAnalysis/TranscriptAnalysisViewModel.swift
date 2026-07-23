//
//  TranscriptAnalysisViewModel.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Drives classify → key points → refine, owns the per-pattern
// caches and the background prefetch, and stores every in-flight `Task` so it can be
// explicitly cancelled before replacement (CLAUDE.md §6). Use cases are injected through
// the initializer; this type never sees a concrete service.

import Foundation
import ShuoCore

/// Drives the transcript analysis screen.
///
/// The flow it orchestrates:
/// 1. Classify the transcript against the catalog subset for the user's purpose.
/// 2. Generate key points for the top-ranked pattern and show them — the user waits only
///    for this one.
/// 3. Prefetch the other two patterns' key points in the background, so switching is
///    instant.
/// 4. On request, regenerate a refined transcript for the selected pattern.
///
/// **Cancellation is the load-bearing concern here** (CLAUDE.md §6). Every overlapping
/// operation has a stored handle that is cancelled before being replaced, and the whole
/// screen can be torn down with `cancelAll()`. A leaked prefetch firing an AI call after
/// the user has dismissed the sheet is the specific bug class this design exists to
/// prevent.
@Observable
@MainActor
public final class TranscriptAnalysisViewModel {

    // MARK: - Observable state

    public private(set) var viewState: TranscriptAnalysisViewState = .analyzing
    /// The working script. Mutated as patterns are chosen and the transcript refined, then
    /// handed to `SaveScriptUseCase`.
    public private(set) var draft: ScriptDraft
    /// The up-to-3 pattern carousel. A child view model, composed rather than absorbed
    /// (CLAUDE.md §5).
    public let carousel: PatternCarouselViewModel
    /// Key points for the selected pattern — always one per component, in order.
    public private(set) var keyPoints: [KeyPoint] = []
    /// True while key points for a newly selected pattern are being generated. An in-place
    /// indicator, not a screen transition.
    public private(set) var isGeneratingKeyPoints = false
    /// True while the refined transcript is being generated.
    public private(set) var isRegeneratingTranscript = false
    /// A failure from selecting a pattern or regenerating, shown inline. Distinct from
    /// `viewState.failed`, which is reserved for the initial load — a failed refinement
    /// must not tear down key points the user can still read.
    public private(set) var actionError: ShuoError?
    public private(set) var isSaving = false
    /// True when the draft has changed since it was last persisted.
    ///
    /// The draft is saved automatically as soon as analysis succeeds, so leaving is never
    /// total loss — but a pattern switch or a regeneration after that point is unsaved
    /// work, and this is what lets ✕ tell the difference between "nothing to lose" and
    /// "you have changes".
    public private(set) var hasUnsavedChanges = false

    // MARK: - Dependencies

    private let availability: any AIAvailabilityChecking
    private let classifyTranscript: ClassifyTranscriptUseCase
    private let generateKeyPoints: GenerateKeyPointsUseCase
    private let regenerateTranscript: RegenerateTranscriptUseCase
    private let saveScript: SaveScriptUseCase

    /// How long to wait between availability checks while the model is warming up.
    ///
    /// Two seconds because the thing being waited on is an asset download measured in
    /// minutes: polling faster only burns wakeups on a screen that is already just a
    /// spinner, and polling much slower would leave the user staring at it for seconds
    /// after the model became usable. Internal rather than a constant so tests can shrink
    /// it — it is not part of the public API and `AppContainer` never sets it.
    var availabilityPollInterval: Duration = .seconds(2)

    // MARK: - Caches

    /// Key points already generated, keyed by pattern. Makes switching back to a pattern
    /// instant and, more importantly, free — an on-device generation is seconds of compute
    /// and battery to reproduce an identical result.
    private var keyPointCache: [SpeechPattern.ID: [KeyPoint]] = [:]
    /// Refined transcripts already generated, keyed by pattern. Same reasoning, and more
    /// valuable still since refinement is the most expensive call in the flow.
    private var refinedCache: [SpeechPattern.ID: String] = [:]

    // MARK: - In-flight work

    private var analysisTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var regenerationTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// Monotonic tags identifying the newest key-point / refinement run.
    ///
    /// Cancelling a `Task` does not unwind it immediately — a superseded run resumes from
    /// its cancelled `await` and executes its `defer` *after* the run that replaced it has
    /// already set the progress flag. Without a tag the loser clears the winner's spinner,
    /// so only the current generation is allowed to reset the flag.
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
    ///
    /// Deliberately duplicated rather than imported: the same string is
    /// `InputScriptViewModel.untitledTitle` in `FeatureSpeechCreation`, and a Feature
    /// package may not depend on another Feature package (CLAUDE.md §4). A four-word
    /// constant is the cheaper of the two costs.
    static let untitledTitle = "Untitled Script"

    /// The script's title, renameable from the analysis screen.
    ///
    /// Settable because this is the only place a title can be changed after creation: the
    /// input step's title field is optional, and without this a user who skipped it would
    /// be stuck with "Untitled Script" forever.
    ///
    /// The setter accepts an empty or whitespace-only value on purpose — it is bound to a
    /// text field, and a user clearing it to retype passes through empty on the way. The
    /// value is normalized by `commitTitle()` instead, so the clear is allowed to stand
    /// while the field is being edited but can never be what gets persisted.
    public var title: String {
        get { draft.title }
        set {
            guard newValue != draft.title else { return }
            draft.title = newValue
            hasUnsavedChanges = true
        }
    }

    /// Settles the title once the user is done editing it: trims surrounding whitespace,
    /// and falls back to `untitledTitle` if that leaves nothing.
    ///
    /// Called when the field loses focus or is submitted, and again from `save()` so a
    /// title cleared and never committed — the user taps ✓ straight from the keyboard —
    /// still cannot reach the repository as an empty string. Restoring the placeholder
    /// beats rejecting the edit or persisting `""`: an untitled script is already a state
    /// the app understands and renders, whereas a blank row in Home is just a broken one.
    ///
    /// Routed through the `title` setter, so an already-clean title stays a no-op and does
    /// not manufacture unsaved changes.
    public func commitTitle() {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? Self.untitledTitle : trimmed
    }
    public var originalTranscript: String { draft.transcript.original }
    /// The refined transcript for the selected pattern, or nil if it has not been
    /// generated yet.
    public var refinedTranscript: String? { draft.transcript.refined }
    public var selectedPattern: SpeechPattern? { draft.selectedPattern }
    /// True when the user has something to regenerate against.
    public var canRegenerateTranscript: Bool {
        selectedPattern != nil && !isRegeneratingTranscript
    }

    // MARK: - Lifecycle

    /// Runs the initial analysis. Safe to call more than once — a second call while the
    /// first is running is ignored rather than starting a competing classification.
    public func start() {
        guard analysisTask == nil else { return }
        analysisTask = Task { [weak self] in
            await self?.runInitialAnalysis()
        }
    }

    /// Cancels every in-flight *generation*. Call from the view's disappearance so a
    /// background prefetch cannot outlive the screen and fire an AI call for a sheet the
    /// user already dismissed.
    ///
    /// An in-flight save is deliberately **not** cancelled. Generations are speculative
    /// and safe to abandon; a save is the one operation whose whole purpose is to survive
    /// the screen going away, and cancelling it here would re-create the data loss that
    /// saving on load exists to prevent. It is short, bounded, and holds only a detached
    /// draft value, so letting it finish costs nothing.
    public func cancelAll() {
        analysisTask?.cancel()
        selectionTask?.cancel()
        prefetchTask?.cancel()
        regenerationTask?.cancel()
        analysisTask = nil
        selectionTask = nil
        prefetchTask = nil
        regenerationTask = nil
    }

    /// Retries after a failed initial analysis.
    public func retry() {
        guard case .failed = viewState else { return }
        cancelAll()
        viewState = .analyzing
        start()
    }

    // MARK: - Initial analysis

    private func runInitialAnalysis() async {
        // A reopened script already carries a full analysis — patterns, a selected one,
        // its key points — persisted the last time it went through this exact flow
        // (ARCHITECTURE.md §3.3: "previously generated data remains available"). Re-
        // classifying here would cost a real AI call for work that's already done, and
        // could silently overrule the user's earlier pattern choice if the model ranks
        // differently on a second pass. `draft.selectedPattern` resolving to nil (a
        // retired catalog pattern) is the one case that still falls through below.
        if !draft.keyPoints.isEmpty, let selectedPattern = draft.selectedPattern {
            loadPersistedAnalysis(selectedPattern: selectedPattern)
            return
        }

        // Ask before generating, not after failing: ...
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
                // `ClassifyTranscriptUseCase` throws rather than returning empty, so this
                // is unreachable — but falling through to `.loaded` with no patterns would
                // strand the user on a blank screen, so fail loudly instead.
                viewState = .failed(.aiGenerationFailed)
                return
            }

            // Selecting before the callback is wired means this does not re-enter
            // `select(_:)` — the initial generation is awaited here so the screen can go
            // straight to `.loaded` with content already on it.
            carousel.select(top)
            try await applyPattern(top)
            guard !Task.isCancelled else { return }

            viewState = .loaded
            // Persist as soon as the analysis is real. Everything before this point could
            // still turn out to be unusable input, but a transcript that classified
            // successfully is worth keeping — and from here the user can leave by ✕, by
            // swipe, or by the app being killed, none of which we get to intercept
            // reliably. The final ✓ updates this record rather than inserting a second
            // one, because `save` carries the assigned id back onto the draft.
            save()
            // Only now does tapping a card do anything; the carousel is not interactive
            // until the screen has loaded.
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
    
    private func loadPersistedAnalysis(selectedPattern: SpeechPattern) {
        carousel.update(patterns: draft.suggestedPatterns)
        carousel.select(selectedPattern)
        keyPoints = draft.keyPoints
        keyPointCache[selectedPattern.id] = draft.keyPoints
        refinedCache[selectedPattern.id] = draft.transcript.refined

        viewState = .loaded
        carousel.onSelect = { [weak self] pattern in
            self?.select(pattern)
        }
        // So switching to one of the other suggested patterns is instant here too.
        startPrefetch(excluding: selectedPattern.id, from: draft.suggestedPatterns)
    }

    /// Waits until on-device generation is possible, returning false if it never will be.
    ///
    /// Only `.modelNotReady` is worth waiting on; the other two unavailable cases are
    /// settled and get their own terminal screen. The wait is a suspended `Task.sleep`
    /// rather than a spin, which is also what makes it cancellable: `cancelAll()` cancels
    /// `analysisTask`, the sleep throws, and the loop exits instead of continuing to poll
    /// for a screen the user has already dismissed (CLAUDE.md §6).
    private func waitForModel() async -> Bool {
        while true {
            let status = await availability.availability()
            guard !Task.isCancelled else { return false }

            switch status {
            case .available:
                // Back to the ordinary spinner if we had been showing the warm-up message.
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

    /// A rejection is about the user's content and gets its own actionable screen; anything
    /// else is a failure they can retry.
    private static func viewState(for error: ShuoError) -> TranscriptAnalysisViewState {
        if case .transcriptNotUsable(let reason) = error {
            return .rejected(reason)
        }
        return .failed(error)
    }

    // MARK: - Pattern selection

    /// Switches to `pattern`, generating its key points if they aren't cached.
    ///
    /// Cancels any in-flight prefetch first. The analyzer serializes requests, so a
    /// background prefetch already running would otherwise make the user's own tap wait
    /// behind work they didn't ask for.
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
            resumePrefetch()
        }
    }

    /// Points the draft at `pattern` and puts its key points on screen, generating them if
    /// they are not already cached.
    private func applyPattern(_ pattern: SpeechPattern) async throws {
        draft.selectedPatternID = pattern.id
        // A refined transcript belongs to the pattern it was generated for, so restore the
        // cached one or clear it — leaving the previous pattern's text on screen under a
        // new pattern's key points would be quietly wrong.
        draft.transcript.refined = refinedCache[pattern.id]
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
        // Only publish if this is still the pattern the user is looking at — a slow
        // generation for a pattern they have since navigated away from must not overwrite
        // what is on screen.
        guard draft.selectedPatternID == pattern.id else { return }
        keyPoints = generated
        draft.keyPoints = generated
    }

    // MARK: - Prefetch

    /// Generates key points for the non-selected patterns, one at a time, in the
    /// background.
    ///
    /// Sequential rather than concurrent on purpose: the analyzer is an actor and the
    /// neural engine runs one generation at a time regardless, so firing three at once
    /// would add memory pressure and contention without finishing any sooner.
    ///
    /// Prefetch failures are swallowed. This is speculative work the user did not ask for;
    /// surfacing an error banner for it would be noise, and selecting that pattern later
    /// retries and reports the failure then, in context.
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
        }
    }

    /// Restarts prefetching for whatever is still uncached after a selection interrupted it.
    private func resumePrefetch() {
        guard let selectedID = draft.selectedPatternID else { return }
        startPrefetch(excluding: selectedID, from: carousel.patterns)
    }

    // MARK: - Refined transcript

    /// Generates the refined transcript for the selected pattern.
    ///
    /// User-triggered rather than automatic: refinement is the most expensive call in the
    /// flow, and running it on every pattern switch would burn time and battery producing
    /// text the user may never scroll to.
    public func regenerate() {
        guard let pattern = selectedPattern else { return }

        regenerationTask?.cancel()
        actionError = nil

        if let cached = refinedCache[pattern.id] {
            draft.transcript.refined = cached
            hasUnsavedChanges = true
            return
        }

        regenerationGeneration &+= 1
        let generation = regenerationGeneration
        isRegeneratingTranscript = true
        regenerationTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == regenerationGeneration { isRegeneratingTranscript = false } }
            do {
                let refined = try await regenerateTranscript(
                    transcript: draft.transcript,
                    pattern: pattern,
                    keyPoints: keyPoints
                )
                try Task.checkCancellation()
                refinedCache[pattern.id] = refined
                // Same guard as key points: don't overwrite the screen if the user has
                // switched patterns while this was generating.
                guard draft.selectedPatternID == pattern.id else { return }
                draft.transcript.refined = refined
                hasUnsavedChanges = true
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

    /// Persists the draft. Updates the reopened script when there is one, inserts otherwise.
    public func save(onSaved: (@MainActor (Script) -> Void)? = nil) {
        guard !isSaving else { return }
        // Last line of defence for the title: ✓ can be tapped straight from the keyboard,
        // so the field may never have lost focus to commit itself.
        commitTitle()

        isSaving = true
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { isSaving = false }
            do {
                let script = try await saveScript(draft)
                try Task.checkCancellation()
                // Carry the assigned id back, so saving twice updates rather than
                // inserting a second copy.
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

    /// Clears an inline error after the user dismisses it.
    public func dismissActionError() {
        actionError = nil
    }
}
