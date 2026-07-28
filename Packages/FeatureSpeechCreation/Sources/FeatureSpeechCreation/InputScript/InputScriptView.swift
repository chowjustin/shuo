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
    private let onConfirm: () async -> Void
    @FocusState private var isTitleFocused: Bool
    @State private var isConfirmingProceed = false

    /// - Parameter onConfirm: Finalizes the active mode and advances the flow. Async
    ///   because Speak mode has real work to do first — ending its session and flushing
    ///   the take — and because what follows depends on the result: a source the user has
    ///   already had analyzed goes straight back to that analysis, anything else is
    ///   transcribed afresh.
    public init(
        viewModel: InputScriptViewModel,
        onBack: @escaping () -> Void,
        onConfirm: @escaping () async -> Void
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onConfirm = onConfirm
    }

    public var body: some View {
        ZStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Title", text: $viewModel.title, axis: .vertical)
                        .font(.system(.largeTitle, weight: .bold))
                        .lineLimit(1...3)
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
                .navigationBarBackButtonHidden(true)
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
                                .font(.title3.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(ShuoColor.pink)
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
        .foregroundStyle(ShuoColor.primaryTextCream)
        .background(ShuoColor.background)
        .presentationDragIndicator(.visible)
        // The whole flow is one sheet, so swipe-dismiss here would tear down the create
        // flow entirely rather than stepping back — a half-filled session is not something
        // to lose to an accidental gesture. ‹ and ✓ are the deliberate exits.
        .interactiveDismissDisabled(true)
    }

    private var fileTooLargeAlert: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red.opacity(0.85))

            Text("File too large.")
                .font(.title3.bold())
                .foregroundStyle(ShuoColor.primaryTextCream)

            // Reads the limit from the domain rather than repeating it — the number and
            // the check it describes used to be able to drift apart.
            Text("Maximum file size: \(MediaLimits.formattedMaxFileSize)")
                .font(.subheadline)
                .foregroundStyle(ShuoColor.secondaryTextCream)

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

    /// ✓. Hands off to the coordinator, which finalizes the active mode and decides where
    /// it goes. The other two modes are left intact — this screen is still reachable, in
    /// both directions, until the flow ends.
    private func confirm() {
        Task { await onConfirm() }
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
                    onBack: { isPresented = false },
                    onConfirm: {}
                )
            }
    }
}
#endif
