//
//  LoadingView.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Shared loading screen reused across extraction/transcription/analysis and the
// 'waiting for model' state. Reads a display model (icon/message) rather than
// `ShuoCore.LoadingContext` directly, keeping this package domain-agnostic. See
// ARCHITECTURE.md §3.1.1, CLAUDE.md §4.

import SwiftUI

/// Centered progress indicator for a step that takes a while.
///
/// Content only, with no cancel button of its own: the presenting screen puts ✕ in its
/// toolbar, and a second cancel affordance here would compete with it.
///
/// Takes a message rather than a `LoadingContext` so this package stays free of domain
/// types; the caller maps its own state to copy.
public struct LoadingView: View {
    /// The animated mascot every step of the pipeline shows. Pass it as `systemImage` to
    /// get the loop instead of an SF Symbol.
    public static let artworkName = "SHUO LOAD"

    /// Decodes the mascot ahead of time, off the main thread, so the first loading screen
    /// of a flow shows it in the frame it appears.
    ///
    /// Worth calling as soon as a flow that ends in a loading screen *begins* — the create
    /// flow does it at the purpose step, which buys the whole of Input Script. Decoding is
    /// a second of work for a 165-frame loop, and the alternative to spending it early is
    /// an empty box on screen while the user waits for something else. Cheap to call more
    /// than once: already decoded and already decoding are both no-ops.
    public static func prewarmArtwork() {
        GifImageLoader.prewarm(artworkName)
    }

    private let systemImage: String
    private let message: String
    private let messageColor: Color
    private let detail: String?

    /// - Parameter detail: optional second line, e.g. a filename or expected duration.
    /// - Parameter messageColor: color for the message text; defaults to `ShuoColor.primaryText`.
    public init(
        systemImage: String = "waveform",
        message: String,
        messageColor: Color = ShuoColor.primaryText,
        detail: String? = nil
    ) {
        self.systemImage = systemImage
        self.message = message
        self.messageColor = messageColor
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: ShuoSpacing.large) {
            if systemImage == Self.artworkName {
                NativeGifView(gifName: Self.artworkName)
                    .frame(width: 160, height: 160)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(ShuoColor.pink)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .accessibilityHidden(true)
            }

            VStack(spacing: ShuoSpacing.small) {
                Text(message)
                    .font(ShuoTypography.headline)
                    .foregroundStyle(messageColor)

                if let detail {
                    Text(detail)
                        .font(ShuoTypography.subtitle)
                        .foregroundStyle(ShuoColor.secondaryText)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ShuoSpacing.xLarge)

            ProgressView()
                .progressViewStyle(.circular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShuoColor.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.map { "\(message). \($0)" } ?? message)
    }
}

// MARK: - Previews

#Preview("Transcribing") {
    LoadingView(
        systemImage: "SHUO LOAD",
        message: "Transcribing your speech…",
        detail: "campus-speech.m4a"
    )
}

#Preview("Analyzing") {
    LoadingView(systemImage: "SHUO LOAD", message: "Analyzing your speech…")
}
