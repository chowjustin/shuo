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

    public init(coordinator: CreateScriptCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ShuoSpacing.medium) {
                    Text("What's the purpose of your speech?")
                        .font(ShuoTypography.title)
                        .foregroundStyle(ShuoColor.primaryText)
                        .padding(.top, ShuoSpacing.small)

                    ForEach(SpeechPurpose.allCases) { purpose in
                        PurposeCard(
                            title: purpose.title,
                            description: purpose.description,
                            isSelected: coordinator.selectedPurpose == purpose,
                            action: { selectPurpose(purpose) }
                        )
                    }
                }
                .padding(ShuoSpacing.medium)
            }
            .background(ShuoColor.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coordinator.close()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(ShuoColor.secondaryText)
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
    }

    private func selectPurpose(_ purpose: SpeechPurpose) {
        inputScriptViewModel = InputScriptViewModel(purpose: purpose)
        coordinator.selectPurpose(purpose)
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
