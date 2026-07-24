//
//  PurposeSelectionView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// No dedicated ViewModel — the coordinator handles which purpose was tapped directly.
// See ARCHITECTURE.md §3.1.1.

import Foundation
import ShuoCore
import ShuoDesignSystem
import SwiftUI

public struct PurposeSelectionView: View {
    private let coordinator: CreateScriptCoordinator
    @State private var selectedPurpose: SpeechPurpose?
    @State private var navigationTask: Task<Void, Never>?

    /// Lets the tapped card render its selected state before the flow moves on.
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
    }
}
