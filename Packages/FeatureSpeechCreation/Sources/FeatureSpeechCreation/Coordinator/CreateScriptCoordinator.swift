//
//  CreateScriptCoordinator.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Observation
import ShuoCore

@Observable
@MainActor
public final class CreateScriptCoordinator {

    public enum Route: Hashable {
        case input
        case loading
        case analysis
    }

    public var path: [Route] = []

    public private(set) var selectedPurpose: SpeechPurpose?
    public private(set) var inputViewModel: InputScriptViewModel?
    public private(set) var analysisDraft: ScriptDraft?

    /// The confirmed source `analysisDraft` was produced from.
    ///
    /// This is what makes stepping back out of analysis cheap: if the user returns to
    /// Input Script, changes nothing, and confirms again, the source they confirm is the
    /// same value — so there is nothing to re-transcribe and nothing to re-analyze, and
    /// they land back on the analysis they left rather than watching the whole on-device
    /// pipeline reproduce it.
    private var analyzedSource: SpeechSource?

    private let onFinish: () -> Void
    private let makeInputScriptViewModel: @MainActor (SpeechPurpose, String?) -> InputScriptViewModel

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
        analysisDraft = nil
        analyzedSource = nil
        path = [.input]
    }

    /// ✓ on Input Script: finalizes the active mode and moves to whichever step that
    /// source needs.
    ///
    /// Does nothing when the active mode produced no source — the button is disabled in
    /// that case, but a Speak take can still finish empty.
    public func confirmInput() async {
        guard let input = inputViewModel else { return }
        guard let source = await input.prepareToProceed() else { return }

        // Unchanged input, and an analysis of it already exists: go straight back to it.
        // The title is the one thing the user can still have edited here, so it travels
        // forward — everything else on that screen is the analysis's own state.
        if analysisDraft != nil, source == analyzedSource {
            analysisDraft?.title = input.resolvedTitle
            path = [.input, .analysis]
            return
        }

        analysisDraft = nil
        analyzedSource = source
        input.beginTranscription(of: source)
        path = [.input, .loading]
    }

    public func dismissLoading() {
        inputViewModel?.dismissLoading()
        path = [.input]
    }

    /// Transcription finished: hand the draft to analysis.
    ///
    /// The Input Script step stays alive behind this rather than being torn down. It holds
    /// the user's recording, and stepping back to it — with that recording still playable
    /// — is a supported move now, not an error path.
    public func beginAnalysis(_ draft: ScriptDraft) {
        analysisDraft = draft
        // Replaces the stack rather than appending: ‹ from analysis belongs back on Input
        // Script, not on the loading screen the user has already passed through.
        path = [.input, .analysis]
    }

    // MARK: - Backward

    public func dismissInputScript() {
        inputViewModel?.discard()
        inputViewModel = nil
        selectedPurpose = nil
        analysisDraft = nil
        analyzedSource = nil
        path.removeAll()
    }

    /// ‹ on the analysis screen: back to Input Script, exactly as the user left it.
    ///
    /// Nothing is discarded here — not the recording, and not the analysis. Both are still
    /// reachable, in either direction, until the user actually leaves the flow.
    public func returnToInput(from draft: ScriptDraft) {
        selectedPurpose = draft.purpose

        guard let input = inputViewModel else {
            // No live step to return to. Reachable only if the step was released while
            // analysis was on screen; rebuilding it from the draft is better than
            // stranding the user on a screen with nowhere to go.
            let rebuilt = makeInputScriptViewModel(draft.purpose, draft.transcript.original)
            rebuilt.restoreTitle(from: draft.title)
            inputViewModel = rebuilt
            analysisDraft = nil
            analyzedSource = nil
            path = [.input]
            return
        }

        input.restoreTitle(from: draft.title)
        input.stashTranscript(draft.transcript.original)
        analysisDraft = draft
        path = [.input]
    }

    // MARK: - Leaving

    /// The user is done with the flow, whether they saved or not.
    ///
    /// The last point at which anything is released — `discard()` tears down the capture
    /// session *and* deletes the recording it produced, which is the only thing that
    /// removes a take whose session already ended (CLAUDE.md §12).
    public func close() {
        inputViewModel?.discard()
        inputViewModel = nil
        selectedPurpose = nil
        analysisDraft = nil
        analyzedSource = nil
        path.removeAll()
        onFinish()
    }
}
