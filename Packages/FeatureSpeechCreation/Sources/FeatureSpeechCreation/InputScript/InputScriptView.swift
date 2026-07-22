//
//  InputScriptView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import ShuoCore
import SwiftUI

public struct InputScriptView: View {
    @Bindable private var viewModel: InputScriptViewModel
    private let onBack: () -> Void
    private let onClose: () -> Void
    private let onProceed: () -> Void
    @FocusState private var isTitleFocused: Bool
    @State private var isConfirmingProceed = false

    /// - Parameter onProceed: Advances the flow to the transcription step. Called only once
    ///   the active mode has actually produced a source, so a mode that finishes empty
    ///   leaves the user here rather than on a loading screen with nothing to transcribe.
    public init(
        viewModel: InputScriptViewModel,
        onBack: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onProceed: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onClose = onClose
        self.onProceed = onProceed
    }

    public var body: some View {
        ZStack {
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
                        Button(action: attemptConfirm) {
                            Image(systemName: "checkmark")
                        }
                        .disabled(!viewModel.hasValidContent)
                        .accessibilityLabel("Confirm")
                    }
                }
                .alert(
                    "Process \(viewModel.mode.title) only?",
                    isPresented: $isConfirmingProceed
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button("Continue", action: confirm)
                } message: {
                    Text(viewModel.discardWarningMessage)
                }
            }
            .blur(radius: viewModel.attachVM.isFileTooLarge ? 8 : 0)
            .animation(.spring(duration: 0.25), value: viewModel.attachVM.isFileTooLarge)

            if viewModel.attachVM.isFileTooLarge {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                fileTooLargeAlert
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: viewModel.attachVM.isFileTooLarge)
        .presentationDragIndicator(.visible)
        // The whole flow is one sheet, so swipe-dismiss here would tear down the create
        // flow entirely rather than stepping back — a half-filled session is not something
        // to lose to an accidental gesture. ✕/back are the deliberate exits.
        .interactiveDismissDisabled(true)
    }

    private var fileTooLargeAlert: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red.opacity(0.85))

            Text("File too large.")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            // Reads the limit from the domain rather than repeating it — the number and
            // the check it describes used to be able to drift apart.
            Text("Maximum file size: \(MediaLimits.formattedMaxFileSize)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                viewModel.attachVM.cancel()
                viewModel.attachVM.isPickerPresented = true
            } label: {
                Text("Try again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
        .frame(width: 300)
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

    // ✓. Only one mode is ever processed, so before committing, warn when another mode
    // still holds content that confirming would silently drop. With nothing to lose,
    // proceed straight through rather than nagging on the common single-mode path.
    private func attemptConfirm() {
        if viewModel.unconfirmedModesWithContent.isEmpty {
            confirm()
        } else {
            isConfirmingProceed = true
        }
    }

    // Finalizes the active mode, then hands its `SpeechSource` to the transcription step
    // — Speak has to end its session and flush the transcript first, which cannot happen
    // synchronously from a button action.
    /// ✓. Finalizes the active mode, discards the other two, and — only if that produced a
    /// source — advances to transcription.
    private func confirm() {
        Task {
            await viewModel.proceed()
            guard viewModel.loadingVM != nil else { return }
            onProceed()
        }
    }
}

#if DEBUG
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
                    onClose: { isPresented = false },
                    onProceed: {}
                )
            }
    }
}
#endif
