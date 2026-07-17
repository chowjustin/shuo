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

                Picker("Input Mode", selection: $viewModel.mode) {
                    ForEach(InputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Each mode owns its own vertical layout — Speak and Attach centre their
                // content and pin a button to the bottom, Write starts at the top. Spacers
                // here would only fight them, and would push Write's first line away from
                // the picker.
                modeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { isTitleFocused = false }
            .navigationTitle("Input \(viewModel.purpose.gerund) Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: confirm) {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!viewModel.hasValidContent)
                    .accessibilityLabel("Confirm")
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
            AttachFileModeView(viewModel: viewModel.attachVM)
        case .speak:
            SpeakModeView(viewModel: viewModel.speakVM)
        case .write:
            WriteModeView(viewModel: viewModel.writeVM)
        }
    }

    // Leaving without confirming has to tear the Speak session down explicitly, or the
    // microphone keeps running behind a screen the user has left.
    private func goBack() {
        viewModel.discard()
        onBack()
    }

    // Finalizes the active mode before leaving — Speak has to end its session and flush
    // the transcript, which cannot happen synchronously from a button action.
    //
    // The resulting `SpeechSource` is deliberately dropped for now: the step that
    // consumes it (transcription and analysis) is not built yet. See ARCHITECTURE.md
    // §3.1.1 on the unbuilt `.loading` route.
    private func confirm() {
        Task {
            _ = await viewModel.prepareToProceed()
            onClose()
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
                    viewModel: .preview(purpose: .persuade),
                    onBack: {},
                    onClose: { isPresented = false }
                )
            }
    }
}
