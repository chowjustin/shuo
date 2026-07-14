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
    @State private var selectedPurpose: SpeechPurpose?

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
                            isSelected: selectedPurpose == purpose,
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
    }

    private func selectPurpose(_ purpose: SpeechPurpose) {
        selectedPurpose = purpose
        coordinator.selectPurpose(purpose)
    }
}

#Preview {
    PurposeSelectionView(coordinator: CreateScriptCoordinator())
}
