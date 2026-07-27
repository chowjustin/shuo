//
//  RootView.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

import FeatureHome
import FeatureSpeechCreation
import FeatureTranscriptAnalysis
import ShuoCore
import SwiftUI

struct RootView: View {
    let container: AppContainer
    @State private var homeViewModel: HomeViewModel
    @State private var coordinator: CreateScriptCoordinator?
    @State private var reopenedDraft: ScriptDraft?

    init(container: AppContainer) {
        self.container = container
        _homeViewModel = State(initialValue: container.makeHomeViewModel())
    }

    var body: some View {
        HomeView(
            viewModel: homeViewModel,
            onTapCreate: {
                coordinator = container.makeCreateScriptCoordinator(onFinish: {
                    coordinator = nil
                    homeViewModel.load()
                })
            },
            onSelectScript: { id in
                Task {
                    if let draft = try? await container.fetchScriptDraft(id: id) {
                        reopenedDraft = draft
                    }
                }
            }
        )
        .sheet(isPresented: isShowingCreateFlow) {
            if let coordinator {
                CreateFlowSheet(container: container, coordinator: coordinator)
            }
        }
        .sheet(isPresented: isShowingReopenFlow) {
            if let reopenedDraft {
                NavigationStack {
                    TranscriptAnalysisView(
                        viewModel: container.makeTranscriptAnalysisViewModel(draft: reopenedDraft),
                        onClose: {
                            self.reopenedDraft = nil
                            homeViewModel.load()
                        }
                    )
                }
            }
        }
    }

    private var isShowingCreateFlow: Binding<Bool> {
        Binding(
            get: { coordinator != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator = nil
                    homeViewModel.load()
                }
            }
        )
    }

    private var isShowingReopenFlow: Binding<Bool> {
        Binding(
            get: { reopenedDraft != nil },
            set: { isPresented in
                if !isPresented {
                    reopenedDraft = nil
                    homeViewModel.load()
                }
            }
        )
    }
}

/// The whole create flow, in one sheet.
///
/// Every step — purpose, input, loading, analysis — is a content swap inside this single
/// sheet rather than a stack of nested presentations. The stacked version flickered: moving
/// to analysis dismissed two sheets and replaced the presenter's content in one update.
///
/// The join lives here rather than in `FeatureSpeechCreation` because that package must not
/// depend on `FeatureTranscriptAnalysis`; the app target is the only place allowed to know
/// both (CLAUDE.md §4). `CreateFlowView` owns everything up to analysis, so this stays a
/// two-way switch rather than duplicating the feature's internal navigation.
///
/// A real `View` rather than an inline `if` in the sheet closure, so reading
/// `coordinator.analysisDraft` registers an observation dependency and the swap fires.
private struct CreateFlowSheet: View {

    let container: AppContainer

    @Bindable var coordinator: CreateScriptCoordinator

    @State private var analysisCache = AnalysisViewModelCache()

    var body: some View {
        CreateFlowView(
            coordinator: coordinator
        ) { draft, onClose, onBack in

            TranscriptAnalysisView(
                viewModel: analysisCache.viewModel(
                    for: draft,
                    make: container.makeTranscriptAnalysisViewModel
                ),
                onClose: onClose,
                onBack: onBack
            )
        }
    }
}

/// Keeps one analysis view model alive per draft, across pushes and pops.
///
/// `NavigationStack` destroys a destination view when it is popped, and with it any state
/// that view owns — so an analysis the user stepped back from would be regenerated from
/// scratch, on device, when they stepped forward again. Holding the view model out here
/// instead means the coordinator can hand back the same draft and get the same screen,
/// patterns, key points and edits included.
///
/// Deliberately *not* `@Observable`: it is a cache read during view construction, and
/// nothing should re-render because it changed.
@MainActor
private final class AnalysisViewModelCache {
    private var draftID: ScriptDraft.ID?
    private var viewModel: TranscriptAnalysisViewModel?

    /// The view model for `draft`, reusing the retained one when it is the same editing
    /// session. A different draft id means genuinely different input, and gets a new one.
    func viewModel(
        for draft: ScriptDraft,
        make: (ScriptDraft) -> TranscriptAnalysisViewModel
    ) -> TranscriptAnalysisViewModel {
        if let viewModel, draftID == draft.id {
            // The title is the one thing Input Script can still have changed on the way
            // back; everything else on this screen belongs to the analysis itself.
            viewModel.applyTitle(draft.title)
            return viewModel
        }

        let fresh = make(draft)
        viewModel = fresh
        draftID = draft.id
        return fresh
    }
}
