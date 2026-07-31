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

    public init(coordinator: CreateScriptCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: ShuoSpacing.large) {
                Text("Tell us your purpose")
                    .font(ShuoTypography.title)
                    .foregroundStyle(ShuoColor.primaryTextCream)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, ShuoSpacing.medium)

                ForEach(SpeechPurpose.allCases) { purpose in
                    PurposeCard(
                        title: purpose.title,
                        description: purpose.description,
                        isSelected: coordinator.selectedPurpose == purpose,
                        action: { selectPurpose(purpose) }
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(coordinator.selectedPurpose == purpose ? "Selected" : "")
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

        .presentationDragIndicator(.visible)
        // The first thing this flow does that the user cannot see: start decoding the
        // loading mascot. Two screens from here it is the whole screen, and buying that
        // second now — while the user is reading three cards and then filling in a
        // script — is free, where paying it then is not (ARCHITECTURE.md #36).
        .task { LoadingView.prewarmArtwork() }
    }

    /// Selects and moves on in the same frame.
    ///
    /// This used to hold the flow for 200 ms so the tapped card could show its selected
    /// state first — which is 200 ms of a tap that appears to have done nothing, on the
    /// screen where the user is most impatient. `PurposeCard` fills on touch-*down* now,
    /// so the answer arrives before the tap even completes and there is nothing left to
    /// wait for.
    ///
    /// The filled state that outlives the tap is the coordinator's `selectedPurpose`, not
    /// a copy held here. That is what makes this screen idle again on the way back: the
    /// coordinator clears it in `dismissInputScript()`, so ‹ from Input Script returns to
    /// three unselected cards rather than to the one the user has just backed out of. A
    /// local `@State` mirror could only ever be a second answer to the same question,
    /// waiting to disagree with the first.
    private func selectPurpose(_ purpose: SpeechPurpose) {
        coordinator.selectPurpose(purpose)
    }
}

#if DEBUG
    #Preview {
        PurposeSelectionPreviewHost()
    }

    private struct PurposeSelectionPreviewHost: View {
        @State private var isPresented = true

        var body: some View {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
                .sheet(isPresented: $isPresented) {
                    CreateFlowView(
                        coordinator: CreateScriptCoordinator(
                            onFinish: { isPresented = false },
                            makeInputScriptViewModel: { purpose, text in
                                .preview(
                                    purpose: purpose,
                                    initialText: text
                                )
                            }
                        )

                    ) { _, _, _ in
                        EmptyView()
                    }
                }
        }
    }
#endif
