//
//  WriteModeView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Write-mode UI: `TextEditor` bound to `WriteModeViewModel.content` with a placeholder
// overlay when empty. See ARCHITECTURE.md §3.1.4.

import ShuoDesignSystem
import SwiftUI

public struct WriteModeView: View {
    @Bindable private var viewModel: WriteModeViewModel
    @FocusState private var isEditorFocused: Bool

    public init(viewModel: WriteModeViewModel) {
        self.viewModel = viewModel
    }

    /// `TextEditor` insets its text inside its frame — roughly 5pt leading and 8pt top.
    /// Left alone, the first line sits indented and low relative to the Title field above,
    /// which reads as a stray gap under the mode picker.
    private static let textInset = (leading: 5.0, top: 8.0)

    public var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.content)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .font(.body)
                .accessibilityLabel("Your ideas")

            if viewModel.content.isEmpty {
                Text("Let's write your ideas.")
                    .font(.body)
                    .foregroundStyle(ShuoColor.secondaryText)
                    // Sits on TextEditor's inset text, not its frame, so the placeholder
                    // and the caret share a baseline.
                    .padding(.leading, Self.textInset.leading)
                    .padding(.top, Self.textInset.top)
                    .allowsHitTesting(false)
            }
        }
        // Cancels the inset for the whole stack, moving editor and placeholder together:
        // the first line now aligns with the Title field's leading edge and sits directly
        // under the picker.
        .padding(.leading, -Self.textInset.leading)
        .padding(.top, -Self.textInset.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Previews
