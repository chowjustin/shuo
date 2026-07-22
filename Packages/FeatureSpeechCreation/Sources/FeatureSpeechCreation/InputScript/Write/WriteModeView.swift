//
//  WriteModeView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Write-mode UI: `TextEditor` bound to `WriteModeViewModel.content` with a placeholder
// overlay when empty. See ARCHITECTURE.md §3.1.4.

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
                .background(Color.clear)
                .font(.system(size: 24))
                .accessibilityLabel("Your ideas")

            if viewModel.content.isEmpty {
                Text("Start typing your ideas.")
                    .font(.system(size: 24))
                    .foregroundStyle(.gray)
                    .padding(.leading, Self.textInset.leading)
                    .padding(.top, Self.textInset.top)
                    .allowsHitTesting(false)
            }
        }

        .padding(.leading, -Self.textInset.leading)
        .padding(.top, -Self.textInset.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Focus the editor as soon as Write mode appears so the user can type immediately.
        .onAppear { isEditorFocused = true }
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
