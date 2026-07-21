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
/// **One button, one meaning: ‹ goes back to Input Script.** Every state shows it, in the
/// same place. While transcribing it cancels the work; on a failure it simply returns. It
/// is deliberately not a ✕ — this is a step inside the flow, not an exit from it, and the
/// user always lands back on the screen they submitted from with their work intact.
///
/// There is no ✓, and the omission is the fix for a real bug rather than a simplification.
/// A per-error "primary action" had to guess what produced the failure, so `noSpeechDetected`
/// offered "choose another file" — reopening a file picker for a user who had just *recorded*
/// something. Errors here describe what went wrong; the input screen is where every one of
/// them is actually resolved, and going back and confirming again is the retry.
public struct LoadingRouteView: View {
    @Bindable private var viewModel: LoadingRouteViewModel
    private let onBack: () -> Void
    private let onFinished: (Transcript) -> Void

    /// Hand-off is one-way and must happen exactly once.
    ///
    /// `.onAppear` fires again whenever the view re-enters the hierarchy — returning from
    /// the background, or SwiftUI re-inserting it — and a second hand-off would build a
    /// fresh draft and restart an analysis already in progress.
    @State private var didHandOff = false

    /// - Parameters:
    ///   - onBack: returns to Input Script. The caller cancels any in-flight transcription
    ///     and leaves every input mode as the user left it.
    ///   - onFinished: hands the original transcript on to analysis. Called automatically
    ///     as soon as there is a transcript — there is no confirmation step.
    public init(
        viewModel: LoadingRouteViewModel,
        onBack: @escaping () -> Void,
        onFinished: @escaping (Transcript) -> Void
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
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
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back to input")
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
            // No confirmation step: the user already chose to transcribe, so showing them
            // the raw transcript and asking them to approve it adds a tap without adding a
            // decision. Analysis takes over from here and shows the transcript anyway.
            //
            // The spinner is what they see for the frame between handing off and the
            // analysis screen replacing this sheet — it continues the loading state rather
            // than flashing a different screen.
            LoadingView(
                systemImage: systemImage(for: .analyzing),
                message: message(for: .analyzing),
                detail: viewModel.sourceDescription
            )
            .onAppear {
                guard !didHandOff else { return }
                didHandOff = true
                onFinished(transcript)
            }
        }
    }

    // MARK: - Actions

    /// ‹. Cancels first, then hands control back, so a transcription can never outlive the
    /// screen that asked for it (CLAUDE.md §6). Safe to call in any state — cancelling
    /// work that already finished or failed is a no-op.
    private func goBack() {
        viewModel.cancel()
        onBack()
    }

    // Every state of this screen is transitional, so none of them names itself — a title
    // appearing for one frame on the way to analysis reads as a screen the user landed on.
    private let navigationTitle = ""

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
