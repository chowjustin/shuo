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
    @Environment(\.scenePhase) private var scenePhase

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
        
        .task { viewModel.start() }
        // Covers every way out — the ‹ button or the whole flow being torn down — so no
        // transcription outlives the screen that asked for it.
        .onDisappear { viewModel.cancel() }
        // If the user backgrounds the app while transcribing, iOS will suspend the work.
        // Cancel explicitly and show a prompt rather than leaving a stale spinner.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { viewModel.interrupt() }
        }
        // Matches Input Script: the create flow is one sheet, so a swipe here would tear
        // the whole session down rather than step back. ‹ is the only exit.
        .interactiveDismissDisabled(true)
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
            ErrorSheet(mascotImageName: "SHUO ERROR", title: copy.title, message: copy.message)

        case .interrupted:
            VStack(spacing: 12) {
                ShuoImage.mascotError
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                Text("Transcription was interrupted.")
                    .font(.headline)
                    .foregroundStyle(ShuoColor.primaryTextCream)
                Text("You left while your speech was being transcribed. Go back and try again.")
                    .foregroundStyle(ShuoColor.secondaryTextCream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

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

    /// Each step still says what it is doing, and names what it is doing it to.
    ///
    /// Naming the purpose — "your persuading script" — is what makes this read as the
    /// user's own work rather than a generic progress screen; keeping the *step* is what
    /// tells someone waiting on a long video that extraction is running rather than that
    /// the app is stuck. Waiting for the model is the exception: nothing is being done to
    /// the script yet, so saying otherwise would be a small lie.
    private func message(for context: LoadingContext) -> String {
        switch context {
        case .extractingAudio: "Getting the audio from your \(scriptDescription)…"
        case .transcribing: "Transcribing your \(scriptDescription)…"
        case .analyzing: "Analyzing your \(scriptDescription)…"
        case .waitingForModel: "Getting the on-device model ready…"
        }
    }

    /// "persuading script" / "inspiring script" / "informing script".
    private var scriptDescription: String {
        "\(viewModel.purpose.gerund.lowercased()) script"
    }

    private func systemImage(for context: LoadingContext) -> String {
        switch context {
        case .extractingAudio, .transcribing, .analyzing, .waitingForModel:
            "SHUO LOAD"
        }
    }
}
