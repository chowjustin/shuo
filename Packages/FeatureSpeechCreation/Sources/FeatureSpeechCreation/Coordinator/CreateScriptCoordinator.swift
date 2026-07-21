//
//  CreateScriptCoordinator.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Observation
import ShuoCore

/// Drives the create-speech flow and owns every piece of state that outlives a single step.
///
/// **One sheet, one step at a time.** Earlier revisions presented Purpose → Input Script →
/// Loading as *stacked* sheets and swapped only the outermost one for analysis. That made
/// the hand-off to analysis tear down two presentations and replace the presenter's content
/// in a single update, which SwiftUI rendered as a visible flicker. Collapsing the whole
/// flow into one sheet whose content switches on `step` removes the stacking entirely, so
/// there is nothing to unwind and nothing to flicker.
///
/// This is the `Route`/`path` stack ARCHITECTURE.md §3.1.1 warned against reintroducing
/// "before it earns its keep". It has now earned it: the flow branches (a rejected
/// transcript goes *back* to input) and the stacked alternative was visibly broken.
@Observable
@MainActor
public final class CreateScriptCoordinator {

    /// Which step the single create-flow sheet is showing.
    ///
    /// An enum rather than a set of optionals so "showing input *and* loading" cannot be
    /// represented — the exact class of contradictory state that produced the flicker
    /// (CLAUDE.md §5).
    public enum Step: Equatable, Sendable {
        case purpose
        case input
        case loading
        case analysis(ScriptDraft)
    }

    public private(set) var step: Step = .purpose
    public private(set) var selectedPurpose: SpeechPurpose?

    /// The live Input Script view model, owned here rather than by a view so it survives
    /// the move into `.loading` — the loading step reads its source, and a failure there
    /// returns to a screen with the user's content still on it.
    public private(set) var inputViewModel: InputScriptViewModel?

    /// The draft being analyzed, when there is one.
    public var analysisDraft: ScriptDraft? {
        if case .analysis(let draft) = step { return draft }
        return nil
    }

    private let onFinish: () -> Void
    private let makeInputScriptViewModel: @MainActor (SpeechPurpose, String?) -> InputScriptViewModel

    /// - Parameter makeInputScriptViewModel: builds the Input Script step for a purpose,
    ///   optionally seeded with text. A factory rather than the services themselves, so the
    ///   coordinator can rebuild that step — which the rejection path needs — without this
    ///   package knowing what a file importer or an audio capturer is (ARCHITECTURE.md §5).
    public init(
        onFinish: @escaping () -> Void,
        makeInputScriptViewModel: @escaping @MainActor (SpeechPurpose, String?) -> InputScriptViewModel
    ) {
        self.onFinish = onFinish
        self.makeInputScriptViewModel = makeInputScriptViewModel
    }

    // MARK: - Forward

    public func selectPurpose(_ purpose: SpeechPurpose) {
        selectedPurpose = purpose
        inputViewModel = makeInputScriptViewModel(purpose, nil)
        step = .input
    }

    /// Moves to the transcription step. The Input Script view model stays alive: it owns
    /// the loading child, and a retryable failure comes straight back here.
    public func beginLoading() {
        guard inputViewModel?.loadingVM != nil else { return }
        step = .loading
    }

    /// Leaves the transcription step, cancelling the in-flight work, and returns to input.
    public func dismissLoading() {
        inputViewModel?.dismissLoading()
        step = .input
    }

    /// Moves on to analysis with a transcribed draft.
    ///
    /// **This is the point of no return, and the only place unconfirmed input is released.**
    /// Everything before it — including a failed transcription — comes back to a step with
    /// the user's work intact in all three modes. From here nothing can reach them: the one
    /// route back, a rejected transcript, rebuilds the step from text rather than resuming
    /// this one. Discarding here rather than at confirm time is what makes "go back and try
    /// again" non-destructive.
    public func beginAnalysis(_ draft: ScriptDraft) {
        inputViewModel?.discardUnconfirmedModes()
        inputViewModel = nil
        step = .analysis(draft)
    }

    // MARK: - Backward

    public func dismissInputScript() {
        inputViewModel?.discard()
        inputViewModel = nil
        selectedPurpose = nil
        step = .purpose
    }

    /// Returns a rejected transcript to Input Script so the user can edit it.
    ///
    /// The one place this flow goes backwards. Everywhere else, replacing the earlier steps
    /// is right because the user is finished with them; a "this isn't a speech" verdict is
    /// precisely the case where the earlier step *is* the fix, and dropping the transcript
    /// would make the user re-record a speech the app is already holding.
    ///
    /// The step is rebuilt rather than resumed — the original recorder and file handles are
    /// gone by now — so the transcript comes back as text in Write mode, which is also the
    /// mode the user needs in order to change it.
    public func returnToInput(rejecting draft: ScriptDraft) {
        selectedPurpose = draft.purpose
        let input = makeInputScriptViewModel(draft.purpose, draft.transcript.original)
        // The step is rebuilt, so everything the user typed has to be carried back
        // explicitly — the transcript through the factory, the title here. Returning from a
        // failure should cost them nothing they entered.
        input.restoreTitle(from: draft.title)
        inputViewModel = input
        step = .input
    }

    /// Tears the whole flow down.
    public func close() {
        inputViewModel?.discard()
        inputViewModel = nil
        onFinish()
    }
}
