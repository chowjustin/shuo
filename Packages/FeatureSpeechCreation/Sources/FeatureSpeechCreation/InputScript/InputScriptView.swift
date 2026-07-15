//
//  InputScriptView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import ShuoCore
import ShuoDesignSystem
import SwiftUI

public struct InputScriptView: View {
    @Bindable private var viewModel: InputScriptViewModel
    private let onBack: () -> Void
    private let onClose: () -> Void
    @FocusState private var isTitleFocused: Bool

    public init(
        viewModel: InputScriptViewModel,
        onBack: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onClose = onClose

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(ShuoColor.aqua)

        UISegmentedControl.appearance().backgroundColor = UIColor(ShuoColor.aquaTint)
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Title", text: $viewModel.title)
                    .font(.system(.largeTitle, weight: .bold))
                    .focused($isTitleFocused)

                HStack(spacing: 8) {
                    Text("Purpose:")
                        .font(.headline)
                    Text(viewModel.purpose.title)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ShuoColor.aqua, in: Capsule())
                }

                Picker("Input Mode", selection: $viewModel.mode) {
                    ForEach(InputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Spacer(minLength: 40)

                HStack {
                    Spacer()
                    modeContent
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Spacer()
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture { isTitleFocused = false }
            .navigationTitle("Input Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch viewModel.mode {
        case .attachFile:
            Text("Attach a file to get started.")
        case .speak:
            Text("Let's hear your ideas.")
        case .write:
            Text("Let's write your ideas.")
        }
    }
}

#Preview {
    InputScriptPreviewHost()
}

private struct InputScriptPreviewHost: View {
    @State private var isPresented = true

    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                InputScriptView(
                    viewModel: InputScriptViewModel(purpose: .persuade),
                    onBack: {},
                    onClose: { isPresented = false }
                )
            }
    }
}
