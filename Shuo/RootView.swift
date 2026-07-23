//
//  RootView.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

import FeatureHome
import FeatureSpeechCreation
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
                container.makeTranscriptAnalysisView(
                    draft: reopenedDraft,
                    onClose: {
                        self.reopenedDraft = nil
                        homeViewModel.load()
                    },
                    onBack: { _ in
                        self.reopenedDraft = nil
                        homeViewModel.load()
                    }
                )
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
    let coordinator: CreateScriptCoordinator

    var body: some View {
        if let draft = coordinator.analysisDraft {
            container.makeTranscriptAnalysisView(
                draft: draft,
                onClose: coordinator.close,
                onBack: coordinator.returnToInput(rejecting:)
            )
        } else {
            CreateFlowView(coordinator: coordinator, onAnalyze: coordinator.beginAnalysis)
        }
    }
}
