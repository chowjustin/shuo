//
//  PurposeSelectionView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `ForEach(SpeechPurpose.allCases)` over `ShuoDesignSystem.PurposeCard`s. No dedicated
// ViewModel — the coordinator handles which purpose was tapped directly. See
// ARCHITECTURE.md §3.1.1.

import Foundation
import ShuoCore
import ShuoDesignSystem
import SwiftUI
 
public struct PurposeSelectionView: View {
    private let coordinator: CreateScriptCoordinator
    @State private var inputScriptViewModel: InputScriptViewModel?
    @State private var selectedPurpose: SpeechPurpose?
    @State private var navigationTask: Task<Void, Never>?
 
    private static let selectionDelay: Duration = .milliseconds(200)
 
    public init(coordinator: CreateScriptCoordinator) {
        self.coordinator = coordinator
    }
 
    public var body: some View {
        NavigationStack{
            ScrollView {
                VStack(alignment: .center, spacing: ShuoSpacing.large) {
                    
                    Text("Tell us your purpose")
                        .font(ShuoTypography.title)
                        .foregroundStyle(ShuoColor.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    
                    ForEach(SpeechPurpose.allCases) { purpose in
                        PurposeCard(
                            title: purpose.title,
                            description: purpose.description,
                            isSelected: selectedPurpose == purpose,
                            action: { selectPurpose(purpose) }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityValue(selectedPurpose == purpose ? "Selected" : "")
                        .accessibilityAction {
                            selectPurpose(purpose)
                        }
                    }
                }
                .padding(ShuoSpacing.large)

            }
            .background(ShuoColor.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        coordinator.close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(ShuoColor.primaryText)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: isShowingInputScript) {
            if let inputScriptViewModel {
                InputScriptView(
                    viewModel: inputScriptViewModel,
                    onBack: { coordinator.dismissInputScript() },
                    onClose: { coordinator.close() }
                )
            }
        }
        .onDisappear {
            navigationTask?.cancel()
        }
    }
 
    private func selectPurpose(_ purpose: SpeechPurpose) {
        selectedPurpose = purpose
 
        navigationTask?.cancel()
        navigationTask = Task {
            try? await Task.sleep(for: Self.selectionDelay)
            guard !Task.isCancelled else { return }
            inputScriptViewModel = InputScriptViewModel(purpose: purpose)
            coordinator.selectPurpose(purpose)
        }
    }
 
    private var isShowingInputScript: Binding<Bool> {
        Binding(
            get: { coordinator.selectedPurpose != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismissInputScript()
                    inputScriptViewModel = nil
                    selectedPurpose = nil
                }
            }
        )
    }
}
 
#Preview {
    PurposeSelectionPreviewHost()
}
 
private struct PurposeSelectionPreviewHost: View {
    @State private var isPresented = true
 
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                PurposeSelectionView(coordinator: CreateScriptCoordinator(onFinish: { isPresented = false }))
            }
    }
}
 
