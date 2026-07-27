//
//  CreateFlowView.swift
//  FeatureSpeechCreation
//

import ShuoCore
import SwiftUI

public struct CreateFlowView<Analysis: View>: View {

    @Bindable private var coordinator: CreateScriptCoordinator
    
    private let analysisBuilder: (ScriptDraft, @escaping () -> Void, @escaping (ScriptDraft) -> Void) -> Analysis
    
    public init(
        coordinator: CreateScriptCoordinator,
        @ViewBuilder analysisBuilder: @escaping (
            ScriptDraft,
            @escaping () -> Void,
            @escaping (ScriptDraft) -> Void
        ) -> Analysis
    ) {
        self._coordinator = Bindable(wrappedValue: coordinator)
        self.analysisBuilder = analysisBuilder
    }
    
    public var body: some View {
        // INILAH YANG MEMBUAT SEMUANYA NATIVE PUSH MODAL
        NavigationStack(path: $coordinator.path) {
            
            PurposeSelectionView(coordinator: coordinator)
                
                .navigationDestination(for: CreateScriptCoordinator.Route.self) { route in
                    
                    switch route {
                        
                    case .input:
                        if let viewModel = coordinator.inputViewModel {
                            InputScriptView(
                                viewModel: viewModel,
                                onBack: coordinator.dismissInputScript,
                                onConfirm: coordinator.confirmInput
                            )
                            .navigationBarBackButtonHidden(true)
                        }
                        
                    case .loading:
                        if let viewModel = coordinator.inputViewModel,
                           let loadingVM = viewModel.loadingVM {
                            LoadingRouteView(
                                viewModel: loadingVM,
                                onBack: coordinator.dismissLoading,
                                onFinished: { transcript in
                                    coordinator.beginAnalysis(viewModel.makeDraft(from: transcript))
                                }
                            )
                            .navigationBarBackButtonHidden(true)
                        }
                        
                    case .analysis:
                        if let draft = coordinator.analysisDraft {
                            // Inject view Analysis dari luar (AppContainer)
                            analysisBuilder(
                                draft,
                                coordinator.close,
                                coordinator.returnToInput(from:)
                            )
                            .navigationBarBackButtonHidden(true)
                        }
                    }
                }
        }
    }
}
