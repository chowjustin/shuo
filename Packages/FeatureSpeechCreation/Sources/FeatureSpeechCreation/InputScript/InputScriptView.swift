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
                        Button(action: confirm) {
                            Image(systemName: "checkmark")
                        }
                        .disabled(!viewModel.hasValidContent)
                        .accessibilityLabel("Confirm")
                    }
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
        .interactiveDismissDisabled(true)
        // A sheet, so the transcription step reads as part of the same stacked flow as
        // Purpose -> Input Script rather than as a separate screen. Swipe-dismiss is a
        // real exit here, which is why the binding's setter cancels rather than just
        // hiding the cover.
        .sheet(isPresented: isLoadingPresented) {
            if let loadingVM = viewModel.loadingVM {
                LoadingRouteView(
                    viewModel: loadingVM,
                    onCancel: viewModel.dismissLoading,
                    onPickAnotherFile: viewModel.retryWithAnotherFile,
                    onFinished: { _ in
                        // The `.analysis` route consumes the transcript here once pattern
                        // generation exists (ARCHITECTURE.md §3.1.1). Until then,
                        // finishing closes the flow.
                        viewModel.dismissLoading()
                        onClose()
                    }
                )
            }
        }
    }

    // The view model exposes `loadingVM` read-only — presentation is driven through its
    // own methods so dismissing always cancels the in-flight transcription, whichever
    // way the cover goes away.
    private var isLoadingPresented: Binding<Bool> {
        Binding(
            get: { viewModel.loadingVM != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissLoading() }
            }
        )
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

    // Finalizes the active mode, then hands its `SpeechSource` to the transcription step
    // — Speak has to end its session and flush the transcript first, which cannot happen
    // synchronously from a button action.
    private func confirm() {
        Task { await viewModel.proceed() }
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
                    onClose: { isPresented = false }
                )
            }
    }
}
#endif
