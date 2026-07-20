//
//  LoadingRouteView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Wires `LoadingContext` (ShuoCore) to `ShuoDesignSystem.LoadingView`, and drives the
// extract → transcribe use-case sequence. See ARCHITECTURE.md §3.1.1; video attachments
// need audio extraction first (CLAUDE.md §12).

import ShuoCore
import ShuoDesignSystem
import SwiftUI

/// The screen shown while a speech is being turned into text — and the screen shown when
/// that fails.
///
/// Every state shares one chrome: ✕ on the left to leave, ✓ on the right to move forward.
/// What ✓ *does* changes with the state (retry, pick another file, finish) but its
/// position never does, matching the Input Script screen underneath.
public struct LoadingRouteView: View {
    @Bindable private var viewModel: LoadingRouteViewModel
    private let onCancel: () -> Void
    private let onPickAnotherFile: () -> Void
    private let onFinished: (Transcript) -> Void

    /// - Parameters:
    ///   - onPickAnotherFile: dismisses this screen and reopens the file picker, for the
    ///     failures where a different file is the actual fix.
    ///   - onFinished: hands the original transcript on. This is the seam the `.analysis`
    ///     route plugs into once pattern generation exists.
    public init(
        viewModel: LoadingRouteViewModel,
        onCancel: @escaping () -> Void,
        onPickAnotherFile: @escaping () -> Void,
        onFinished: @escaping (Transcript) -> Void
    ) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        self.onPickAnotherFile = onPickAnotherFile
        self.onFinished = onFinished
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: cancel) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: confirm) {
                            Image(systemName: "checkmark")
                        }
                        // Nothing to confirm until there is a result or a failure to act
                        // on; the button stays in place so the chrome does not jump.
                        .disabled(confirmAction == nil)
                        .accessibilityLabel(confirmAccessibilityLabel)
                    }
                }
        }
        .task { viewModel.start() }
        // Covers every way out — swipe-dismiss, the ✕ button, or the whole flow being
        // torn down — so no transcription outlives the screen that asked for it.
        .onDisappear { viewModel.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewState {
        case .loading(let context):
            LoadingView(
                systemImage: systemImage(for: context),
                message: message(for: context),
                detail: viewModel.sourceDescription
            )

        case .failed(let error):
            let copy = TranscriptionErrorCopy(error: error)
            ErrorSheet(systemImage: copy.systemImage, title: copy.title, message: copy.message)

        case .finished(let transcript):
            // Temporary terminus. The `.analysis` route consumes this transcript once
            // `SpeechAnalyzing` lands; until then the flow ends by showing what it
            // produced, so the transcription path is verifiable end to end.
            TranscriptPreviewView(transcript: transcript)
        }
    }

    // MARK: - Actions

    private func cancel() {
        viewModel.cancel()
        onCancel()
    }

    private func confirm() {
        confirmAction?()
    }

    /// What ✓ does in the current state, or nil when there is nothing to confirm yet.
    ///
    /// Derived rather than stored so the button cannot fall out of step with the state,
    /// and so `disabled` and the tap handler are always driven by the same value.
    private var confirmAction: (() -> Void)? {
        switch viewModel.viewState {
        case .loading:
            return nil

        case .finished(let transcript):
            return { onFinished(transcript) }

        case .failed(let error):
            switch TranscriptionErrorCopy(error: error).primaryAction {
            case .pickAnotherFile: return onPickAnotherFile
            case .retry: return { viewModel.start() }
            // Nothing in-app will fix a denied permission, so ✓ leaves rather than
            // offering a retry that cannot work.
            case .close: return cancel
            }
        }
    }

    private var confirmAccessibilityLabel: String {
        switch viewModel.viewState {
        case .loading: "Confirm"
        case .finished: "Done"
        case .failed(let error): TranscriptionErrorCopy(error: error).primaryActionTitle
        }
    }

    private var navigationTitle: String {
        switch viewModel.viewState {
        case .loading: ""
        case .failed: ""
        case .finished: "Transcript"
        }
    }

    // MARK: - LoadingContext -> copy
    //
    // Lives here rather than on `LoadingContext` so the domain stays free of UI wording,
    // and `LoadingView` stays free of domain types.

    private func message(for context: LoadingContext) -> String {
        switch context {
        case .extractingAudio: "Getting the audio from your video…"
        case .transcribing: "Transcribing your speech…"
        case .analyzing: "Analyzing your speech…"
        case .waitingForModel: "Getting the on-device model ready…"
        }
    }

    private func systemImage(for context: LoadingContext) -> String {
        switch context {
        case .extractingAudio: "film"
        case .transcribing: "waveform"
        case .analyzing: "sparkles"
        case .waitingForModel: "arrow.down.circle.dotted"
        }
    }
}

/// Shows the finished transcript.
///
/// Scaffolding for the seam described above: it exists so the attach-file path can be
/// verified before analysis is built, and should be *replaced* by the `.analysis` route
/// rather than grown.
private struct TranscriptPreviewView: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: ShuoSpacing.medium) {
            Text("\(transcript.originalWordCount) words")
                .font(ShuoTypography.caption)
                .foregroundStyle(ShuoColor.secondaryText)

            ScrollView {
                Text(transcript.original)
                    .font(ShuoTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(ShuoSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ShuoColor.background)
    }
}
