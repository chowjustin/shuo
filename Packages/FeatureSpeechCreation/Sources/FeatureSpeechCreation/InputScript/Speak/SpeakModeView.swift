//
//  SpeakModeView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Speak-mode UI: record/pause/resume controls plus `ShuoDesignSystem.WaveformView`
// bound to `SpeakModeViewModel`.

import ShuoDesignSystem
import SwiftUI

public struct SpeakModeView: View {
    private let viewModel: SpeakModeViewModel

    public init(viewModel: SpeakModeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlButton
                .padding(.bottom, 40)
        }
        .task { await viewModel.prepare() }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.viewState {
        case .idle:
            Text("Let's hear your ideas.")
                .foregroundStyle(ShuoColor.secondaryText)

        case .requestingPermission:
            ProgressView()

        case .permissionDenied:
            messagePanel(
                icon: "mic.slash",
                message: "Shuo needs microphone access to record your ideas.",
                action: ("Open Settings", openSettings)
            )

        case .recording, .paused, .finished:
            capturePanel

        case .failed(let message):
            messagePanel(icon: "exclamationmark.triangle", message: message, action: nil)
        }
    }

    private var capturePanel: some View {
        VStack(spacing: ShuoSpacing.xLarge) {
            WaveformView(samples: viewModel.displaySamples)

            Text(viewModel.formattedDuration)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(ShuoColor.primaryText)
                .accessibilityLabel("Recorded \(viewModel.formattedDuration)")

            debugTranscriptPanel // DEBUG_LIVE_TRANSCRIPT
        }
        .padding(.horizontal, ShuoSpacing.large)
    }

    private func messagePanel(
        icon: String,
        message: String,
        action: (title: String, handler: () -> Void)?
    ) -> some View {
        VStack(spacing: ShuoSpacing.medium) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(ShuoColor.secondaryText)

            Text(message)
                .foregroundStyle(ShuoColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ShuoSpacing.xLarge)

            if let action {
                Button(action.title, action: action.handler)
                    .font(.subheadline.bold())
                    .foregroundStyle(ShuoColor.pink)
            }
        }
    }

    // MARK: - Control button

    @ViewBuilder
    private var controlButton: some View {
        switch viewModel.viewState {
        case .idle:
            recordButton(icon: "mic.fill", emphasis: .filled, label: "Start recording")
        case .recording:
            recordButton(icon: "pause.fill", emphasis: .outlined, label: "Pause recording")
        case .paused, .finished:
            recordButton(icon: "play.fill", emphasis: .filled, label: "Resume recording")
        case .requestingPermission, .permissionDenied, .failed:
            EmptyView()
        }
    }

    private func recordButton(
        icon: String,
        emphasis: CircularIconButton.Emphasis,
        label: String
    ) -> some View {
        CircularIconButton(systemImage: icon, emphasis: emphasis, accessibilityTitle: label) {
            viewModel.primaryAction()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: DEBUG_LIVE_TRANSCRIPT — temporary; delete this property and its call site in
    // `capturePanel` above. Nothing else in this view depends on it.
    @ViewBuilder
    private var debugTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: ShuoSpacing.xSmall) {
            Text("DEBUG · live transcript")
                .font(.caption2.bold())
                .foregroundStyle(ShuoColor.secondaryText)

            ScrollView {
                Text(viewModel.debugLiveTranscript.isEmpty ? "…" : viewModel.debugLiveTranscript)
                    .font(.caption)
                    .foregroundStyle(ShuoColor.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 96)
        }
        .padding(ShuoSpacing.small)
        .background(ShuoColor.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    // MARK: END DEBUG_LIVE_TRANSCRIPT
}
