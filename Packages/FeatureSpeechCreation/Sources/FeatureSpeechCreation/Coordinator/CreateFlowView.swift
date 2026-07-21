//
//  CreateFlowView.swift
//  FeatureSpeechCreation
//

import ShuoCore
import SwiftUI

/// The create-speech flow up to the point analysis takes over: Purpose → Input Script →
/// Loading, as content swaps inside a single sheet.
///
/// One view switching on `CreateScriptCoordinator.Step` rather than a chain of nested
/// `.sheet` presentations. The chain looked natural but transitioned badly: handing off to
/// analysis dismissed two stacked sheets and replaced the presenter's content in one
/// update, which rendered as a flicker. There is nothing to unwind here.
///
/// Analysis is deliberately *not* a case in this view. It lives in `FeatureTranscriptAnalysis`,
/// and Feature packages must not depend on each other (CLAUDE.md §4) — so this reports the
/// finished draft through `onAnalyze` and the app target, which is allowed to know both,
/// composes them.
public struct CreateFlowView: View {

    private let coordinator: CreateScriptCoordinator
    private let onAnalyze: (ScriptDraft) -> Void

    public init(
        coordinator: CreateScriptCoordinator,
        onAnalyze: @escaping (ScriptDraft) -> Void
    ) {
        self.coordinator = coordinator
        self.onAnalyze = onAnalyze
    }

    public var body: some View {
        switch coordinator.step {
        case .purpose:
            PurposeSelectionView(coordinator: coordinator)

        case .input:
            if let viewModel = coordinator.inputViewModel {
                InputScriptView(
                    viewModel: viewModel,
                    onBack: coordinator.dismissInputScript,
                    onClose: coordinator.close,
                    onProceed: coordinator.beginLoading
                )
            }

        case .loading:
            if let viewModel = coordinator.inputViewModel, let loadingVM = viewModel.loadingVM {
                LoadingRouteView(
                    viewModel: loadingVM,
                    // Returns to input with every mode untouched — the confirmed take is
                    // still there and still confirmable, so retrying is just ‹ then ✓.
                    onBack: coordinator.dismissLoading,
                    onFinished: { transcript in
                        onAnalyze(viewModel.makeDraft(from: transcript))
                    }
                )
            }

        case .analysis:
            // Owned by the app target, which swaps this whole view out. Rendering nothing
            // here is correct rather than a gap — see the type doc.
            EmptyView()
        }
    }
}
