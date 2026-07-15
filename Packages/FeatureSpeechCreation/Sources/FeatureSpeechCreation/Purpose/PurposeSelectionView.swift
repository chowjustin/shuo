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
<<<<<<< Updated upstream
    @State private var inputScriptViewModel: InputScriptViewModel?

=======
    @State private var selectedPurpose: SpeechPurpose?
    @State private var navigationTask: Task<Void, Never>?
    
    private static let selectionDelay: Duration = .milliseconds(500)
    
>>>>>>> Stashed changes
    public init(coordinator: CreateScriptCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        GeometryReader { geometry in
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
                            isSelected: coordinator.selectedPurpose == purpose,
                            action: { selectPurpose(purpose) }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityValue(selectedPurpose == purpose ? "Selected" : "")                    }
                }
                .padding(ShuoSpacing.medium)
                .frame(minHeight: geometry.size.height)
            }
        }
<<<<<<< Updated upstream
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
    }

    private func selectPurpose(_ purpose: SpeechPurpose) {
        inputScriptViewModel = InputScriptViewModel(purpose: purpose)
        coordinator.selectPurpose(purpose)
=======
        .background(ShuoColor.background)
        .overlay(alignment: .topTrailing) {
            Button {
                coordinator.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ShuoColor.primaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(ShuoColor.closeButtonBackground))
            }
            .accessibilityLabel("Close")
            .padding(ShuoSpacing.medium)
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
            coordinator.selectPurpose(purpose)
        }
>>>>>>> Stashed changes
    }

    private var isShowingInputScript: Binding<Bool> {
        Binding(
            get: { coordinator.selectedPurpose != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismissInputScript()
                    inputScriptViewModel = nil
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
 

