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
    private let systemImage: String
    private let message: String
    private let detail: String?

    /// - Parameter detail: optional second line, e.g. a filename or expected duration.
    public init(
        systemImage: String = "waveform",
        message: String,
        detail: String? = nil
    ) {
        self.systemImage = systemImage
        self.message = message
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: ShuoSpacing.large) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(ShuoColor.pink)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .accessibilityHidden(true)

            VStack(spacing: ShuoSpacing.small) {
                Text(message)
                    .font(ShuoTypography.headline)
                    .foregroundStyle(ShuoColor.primaryText)

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
