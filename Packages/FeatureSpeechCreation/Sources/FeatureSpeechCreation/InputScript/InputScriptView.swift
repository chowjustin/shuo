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
        VStack(alignment: .leading, spacing: 20) {
            TextField("Title", text: $viewModel.title, axis: .vertical)
                .font(.system(.largeTitle, weight: .bold))
                .lineLimit(1 ... 3)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit { isTitleFocused = false }
                .onChange(of: viewModel.title) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    viewModel.title = newValue.replacingOccurrences(of: "\n", with: "")
                    isTitleFocused = false
                }

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
        .sheet(isPresented: Binding(
            get: { viewModel.attachVM.isFileTooLarge },
            set: {
                if !$0 {
                    viewModel.attachVM.cancel()
                }
            }
        )) {
            NavigationStack {
                ErrorSheet(
                    mascotImageName: "SHUO ERROR",
                    title: "File too large.",
                    message: "Maximum file size: \(MediaLimits.formattedMaxFileSize)"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.attachVM.cancel()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .foregroundStyle(ShuoColor.primaryTextCream)
        .background(ShuoColor.background)
        .presentationDragIndicator(.visible)
        // The whole flow is one sheet, so swipe-dismiss here would tear down the create
        // flow entirely rather than stepping back — a half-filled session is not something
        // to lose to an accidental gesture. ‹ and ✓ are the deliberate exits.
        .interactiveDismissDisabled(true)
        // Settles the name a blank title falls back to while the user is still working, so
        // ✓ never waits on a store read. Idempotent, which matters because this step is
        // re-entered rather than rebuilt and so this runs again on the way back.
        .task { viewModel.prepareUntitledPlaceholder() }
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

    /// ‹. Leaving without confirming has to tear the Speak session down explicitly, or the
    /// microphone keeps running behind a screen the user has left — but that is the
    /// coordinator's call to make, not this view's. It discards as part of leaving, and it
    /// is the only one that knows whether this tap is still the one on top of the stack.
    private func goBack() {
        onBack()
    }

    /// ✓. Only one mode is ever processed, so before committing, warn when another mode
    /// still holds content that confirming would silently drop. With nothing to lose,
    /// proceed straight through rather than nagging on the common single-mode path.
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

    #Preview("File Too Large") {
        FileTooLargePreviewHost()
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

    private struct FileTooLargePreviewHost: View {
        @State private var isPresented = true
        @State private var vm = InputScriptViewModel(
            purpose: .persuade,
            fileImporter: TooLargePreviewFileImporting(),
            makeAudioCapturer: { PreviewAudioCapturing() },
            microphonePermissions: PreviewMicrophonePermissionProviding(status: .granted),
            audioPlayer: PreviewAudioPlaying(),
            recordingDeleter: PreviewAudioRecordingDeleting(),
            generateTranscript: GenerateTranscriptUseCase(transcriber: PreviewSpeechTranscribing()),
            nextUntitledTitle: NextUntitledScriptTitleUseCase(repository: PreviewScriptRepository())
        )

        var body: some View {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .sheet(isPresented: $isPresented) {
                    InputScriptView(
                        viewModel: vm,
                        onBack: { isPresented = false },
                        onConfirm: {}
                    )
                }
                .task {
                    vm.mode = .attachFile
                    vm.attachVM.fileSelected(url: URL(filePath: "/tmp/huge.mp4"))
                    await vm.attachVM.importTask?.value
                }
        }
    }

    private struct TooLargePreviewFileImporting: FileImporting {
        func importFile(from _: URL) async throws -> ImportedMedia {
            throw ShuoError.fileTooLarge
        }
    }
#endif
