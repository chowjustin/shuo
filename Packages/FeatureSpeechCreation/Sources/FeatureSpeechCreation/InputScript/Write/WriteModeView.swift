//
//  WriteModeView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Write-mode UI: `TextEditor` bound to `WriteModeViewModel.content` with a placeholder
// overlay when empty. See ARCHITECTURE.md §3.1.4.

import Foundation
import SwiftUI

struct WriteView: View {

    @StateObject private var viewModel = WriteViewModel()

    @FocusState private var titleFocused: Bool
    @FocusState private var scriptFocused: Bool

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            // Editable Title
            TextField(
                "",
                text: $viewModel.title,
                prompt:
                    Text("Title")
                    .foregroundColor(.primary.opacity(0.35))
            )
            .font(.system(size: 42, weight: .bold))
            .textFieldStyle(.plain)
            .focused($titleFocused)

            // Script Editor
            ZStack(alignment: .topLeading) {

                if viewModel.script.isEmpty {
                    Text("Start typing your ideas.")
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }

                TextEditor(text: $viewModel.script)
                    .font(.system(size: 24))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($scriptFocused)
            }

            Spacer()

        }
        .padding()
        .onAppear {
            titleFocused = true
        }
        .toolbar {

            ToolbarItem(placement: .topBarTrailing) {

                Button {

                    viewModel.saveScript()

                } label: {

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.pink)

                }

            }

        }
    }
}

#Preview {
    WriteView()
}
