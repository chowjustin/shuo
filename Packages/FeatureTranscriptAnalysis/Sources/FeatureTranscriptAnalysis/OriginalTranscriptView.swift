//
//  OriginalTranscriptView.swift
//  FeatureTranscriptAnalysis
//
//  Created by rasyel on 21/07/26.
//

import ShuoDesignSystem
import SwiftUI

/// Shows the original script full-screen, to read.
///
/// **Read-only by design.** This used to be an editor: saving a change here re-ran the
/// entire pipeline from the new text, behind a confirmation warning that the patterns, key
/// points and refinements would all be replaced. That gave a screen whose whole job is "let
/// me check what I actually said" the most destructive action in the app, one keystroke
/// away. What the user comes here to do is read, so reading is all it offers — no editor,
/// no save, nothing to confirm.
///
/// The text fills the screen rather than sitting in a fixed-height box: a script is as long
/// as it is, and a scrolling box inside a scrolling screen gives the reader two things to
/// scroll and no sense of how much is left. The bordered card is kept, now as a frame
/// around the whole thing.
public struct OriginalTranscriptView: View {

    private let originalText: String
    private let onBack: () -> Void

    /// - Parameter onBack: returns to the analysis screen.
    public init(
        originalText: String,
        onBack: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.onBack = onBack
    }

    private var wordCount: Int {
        originalText.split(whereSeparator: \.isWhitespace).count
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                scriptCard(minHeight: proxy.size.height - (ShuoSpacing.medium * 2))
                    .padding(ShuoSpacing.medium)
            }
        }
        .background(ShuoColor.background)
        .navigationTitle("Original Script")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back to analysis")
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// - Parameter minHeight: how tall the card is when the script is short. The stretch
    ///   is applied *inside* the background and border so they stretch with it — applied
    ///   outside, the frame would grow while the outline stayed wrapped around the text.
    private func scriptCard(minHeight: CGFloat) -> some View {
        Text(originalText)
            .font(ShuoTypography.body)
            .foregroundStyle(ShuoColor.primaryTextCream)
            // Reading is the point, and a user who wants a line of their own words back
            // should be able to take it without an edit mode.
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ShuoSpacing.medium)
            .frame(maxWidth: .infinity, minHeight: max(0, minHeight), alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ShuoColor.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ShuoColor.pink, lineWidth: 2)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Original script")
            .accessibilityValue(originalText)
            .accessibilityHint("Contains \(wordCount) words.")
    }
}

// MARK: - Preview

#Preview("Original Script") {
    NavigationStack {
        OriginalTranscriptView(
            originalText: """
                Um, okay, so hi everyone. Today I kind of wanted to talk about clubs and \
                organizations on campus, and why I think joining one is the single best \
                thing you can do in your first year.
                """,
            onBack: {}
        )
    }
}
