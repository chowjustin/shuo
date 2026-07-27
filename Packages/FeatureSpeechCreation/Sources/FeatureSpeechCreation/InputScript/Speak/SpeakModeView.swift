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

    /// The inline replay control beside the waveform. Smaller than `CircularIconButton` on
    /// purpose: hearing the take back sits *under* recording it in the hierarchy, and two
    /// controls of equal weight would read as two equally likely next steps.
    private static let replayButtonDiameter: CGFloat = 44

    public init(viewModel: SpeakModeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
                .padding(.bottom, 40)
        }
        .task { await viewModel.prepare() }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.viewState {
        case .idle:
            VStack(spacing: 16) {
                Image("SHUO LISTEN")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)

                Text("Let's hear your ideas.")
                    .foregroundStyle(ShuoColor.secondaryTextCream)
            }

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
            HStack(spacing: ShuoSpacing.medium) {
                if viewModel.canReplay {
                    replayButton
                }

                // The playhead only dims bars while something is actually playing, so a
                // paused take still reads as a whole recording rather than a half-empty one.
                WaveformView(
                    samples: viewModel.displaySamples,
                    progress: viewModel.isPlayingBack ? viewModel.playbackProgress : nil
                )
            }

            Text(viewModel.formattedTimeLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(ShuoColor.primaryText)
                .accessibilityLabel(
                    viewModel.isPlayingBack
                        ? "Playing, \(viewModel.formattedTimeLabel)"
                        : "Recorded \(viewModel.formattedDuration)"
                )

            if let playbackError = viewModel.playbackError {
                Text(playbackError)
                    .font(.caption)
                    .foregroundStyle(ShuoColor.error)
                    .multilineTextAlignment(.center)
            }

            debugTranscriptPanel // DEBUG_LIVE_TRANSCRIPT
        }
        .padding(.horizontal, ShuoSpacing.large)
    }

    private var replayButton: some View {
        Button(action: viewModel.togglePlayback) {
            ZStack {
                Circle().stroke(ShuoColor.pink, lineWidth: 2)
                Image(systemName: viewModel.isPlayingBack ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .foregroundStyle(ShuoColor.pink)
            }
            .frame(width: Self.replayButtonDiameter, height: Self.replayButtonDiameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isPlayingBack ? "Pause playback" : "Play recording")
    }

    private func messagePanel(
        icon: String,
        message: String,
        action: (title: String, handler: () -> Void)?
    ) -> some View {
        VStack(spacing: ShuoSpacing.medium) {
            Image("SHUO ERROR")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

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

    // MARK: - Controls

    /// The primary record control, with Retake beneath it once there is a take to replace
    /// — the same pairing, in the same place, as Attach File's Reupload File.
    private var controls: some View {
        VStack(spacing: ShuoSpacing.medium) {
            controlButton

            if viewModel.canRetake {
                PillButton("Retake") { viewModel.retake() }
                    .accessibilityLabel("Retake recording")
            }
        }
    }

    @ViewBuilder
    private var controlButton: some View {
        switch viewModel.viewState {
        case .idle:
            recordButton(icon: "mic.fill", emphasis: .filled, label: "Start recording")
        case .recording:
            recordButton(icon: "pause.fill", emphasis: .outlined, label: "Pause recording")
        case .paused:
            recordButton(icon: "play.fill", emphasis: .filled, label: "Resume recording")
        // A finished take's session is over and cannot be added to — offering a resume
        // control that could only fail would be worse than offering none.
        case .finished, .requestingPermission, .permissionDenied, .failed:
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

#if DEBUG
#Preview("Idle") {
    SpeakModeView(viewModel: .preview())
        .background(ShuoColor.background)
}
#endif
