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
        path.append(.input)
    }

    public func beginLoading() {
        guard inputViewModel?.loadingVM != nil else { return }
        path.append(.loading)
    }

    public func dismissLoading() {
        inputViewModel?.dismissLoading()
        _ = path.popLast()
    }

    public func beginAnalysis(_ draft: ScriptDraft) {
        inputViewModel?.discardUnconfirmedModes()
        inputViewModel = nil
        analysisDraft = draft
        path.append(.analysis)
    }

    // MARK: - Backward
    public func dismissInputScript() {
        inputViewModel?.discard()
        inputViewModel = nil
        selectedPurpose = nil
        path.removeAll()
    }

    public func returnToInput(rejecting draft: ScriptDraft) {
        selectedPurpose = draft.purpose
        let input = makeInputScriptViewModel(draft.purpose, draft.transcript.original)
        input.restoreTitle(from: draft.title)
        inputViewModel = input
        analysisDraft = nil
        path = [.input]
    }

    public func close() {
        inputViewModel?.discard()
        inputViewModel = nil
        analysisDraft = nil
        path.removeAll()
        onFinish()
    }
}
