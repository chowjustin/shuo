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
    @FocusState private var isContentFocused: Bool

    public init(viewModel: WriteModeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.content.isEmpty {
                Text("Start typing your ideas.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }

            TextEditor(text: $viewModel.content)
                .font(.system(size: 20))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isContentFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Empty") {
    WriteModeView(viewModel: WriteModeViewModel())
}

#Preview("With content") {
    let vm = WriteModeViewModel()
    vm.content = "My speech starts here..."
    return WriteModeView(viewModel: vm)
}
