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

    private static let textInset = (leading: 5.0, top: 8.0)

    public var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.content)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .font(.body)
                .accessibilityLabel("Your ideas")

            // Ghost text while actively typing with nothing entered yet — not the idle
            // state. Only shown while focused, so it doesn't fight the centered idle
            // copy below.
            if viewModel.content.isEmpty && isEditorFocused {
                Text("Let's write your ideas.")
                    .font(.body)
                    .foregroundStyle(ShuoColor.secondaryTextCream)
                    .padding(.leading, Self.textInset.leading)
                    .padding(.top, Self.textInset.top)
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, -Self.textInset.leading)
        .padding(.top, -Self.textInset.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            // Idle state: mirrors Speak mode's centered mascot + copy. Tapping anywhere
            // still reaches the TextEditor underneath (allowsHitTesting is false here),
            // which focuses it and swaps this out for the top-left editor.
            if viewModel.content.isEmpty && !isEditorFocused {
                VStack(spacing: 12) {
                    Image("SHUO WRITE")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)

                    Text("Tap anywhere to write.")
                        .font(.body)
                        .foregroundStyle(ShuoColor.secondaryTextCream)
                }
                .offset(y: -60) // adjust this value — negative moves it up
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    WriteModeView(viewModel: WriteModeViewModel())
        .padding()
}

#Preview("With content") {
    let viewModel = WriteModeViewModel()
    viewModel.content = "Joining a campus organization is the fastest way to build the network you will rely on after graduation."
    return WriteModeView(viewModel: viewModel)
        .padding()
}
