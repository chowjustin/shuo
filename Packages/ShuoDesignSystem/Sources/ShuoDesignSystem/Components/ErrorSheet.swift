//
//  ErrorSheet.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 20/07/26.
//

// Sheet content for a failed operation: glyph, title, and message centered. Takes
// primitives only — the ShuoError -> copy mapping belongs to the feature package
// (CLAUDE.md §4).

import SwiftUI

/// Centered explanation of why something failed.
///
/// Content only, with no buttons of its own: the presenting screen puts its actions in a
/// toolbar (✕ / ✓), so an action pinned inside here would be a second, competing way to
/// do the same thing.
///
/// Deliberately primitive in its inputs — this package never imports `ShuoCore`, so the
/// caller resolves its domain error into a glyph and two strings first. That keeps the
/// sheet previewable in isolation and reusable for any failure, not just transcription.
public struct ErrorSheet: View {
    private let systemImage: String
    private let mascotImageName: String?
    private let title: String
    private let message: String

    /// - Parameters:
    ///   - systemImage: SF Symbol shown above the title (fallback when no mascot).
    ///   - mascotImageName: Optional asset catalog image name; when provided, replaces the SF Symbol.
    public init(
        systemImage: String = "exclamationmark.triangle.fill",
        mascotImageName: String? = nil,
        title: String,
        message: String
    ) {
        self.systemImage = systemImage
        self.mascotImageName = mascotImageName
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: ShuoSpacing.large) {
            if let mascotImageName {
                Image(mascotImageName, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(ShuoColor.error)
                    .accessibilityHidden(true)
            }

            VStack(spacing: ShuoSpacing.small) {
                Text(title)
                    .font(ShuoTypography.sheetTitle)
                    .foregroundStyle(ShuoColor.primaryTextCream)

                Text(message)
                    .font(ShuoTypography.subtitle)
                    .foregroundStyle(ShuoColor.secondaryTextCream)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ShuoSpacing.xLarge)
        }
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShuoColor.background)
        // One announcement for the whole sheet, so VoiceOver reads the failure as a
        // sentence rather than as three unrelated fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Previews

#Preview("No speech") {
    ErrorSheet(
        systemImage: "waveform.slash",
        title: "We couldn't hear any speech.",
        message: "This file seems to be silent, or contains only music or background noise."
    )
}

#Preview("Generic failure") {
    ErrorSheet(
        title: "Transcription failed.",
        message: "Something went wrong while reading this file. Please try again."
    )
}
