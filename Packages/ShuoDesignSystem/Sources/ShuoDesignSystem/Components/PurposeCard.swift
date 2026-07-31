//
//  PurposeCard.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Reusable card for the Purpose screen (persuade/inspire/inform). Takes primitive
// display values (title, description, selected state, tap closure) — never a
// `ShuoCore.SpeechPurpose` directly, keeping this package previewable in isolation
// (CLAUDE.md §4).

import Foundation
import SwiftUI

/// A tappable card that fills for two reasons, and looks the same for both: a finger is on
/// it right now, or it is the one the caller says is selected.
///
/// The press half is what makes the screen feel answered. `.plain` gives custom content no
/// highlight at all, so a tap used to look identical to no tap until the next screen slid
/// in — and on a slow frame that gap is long enough to tap again.
public struct PurposeCard: View {
    private let title: String
    private let description: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        title: String,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // Deliberately empty: `Style` draws the card instead. Press state lives on the
            // button's configuration, nothing inside a label can read it, and the fill it
            // drives has to reach the text colours as well as the background.
            EmptyView()
        }
        .buttonStyle(Style(isSelected: isSelected, card: card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// - Parameter isHighlighted: filled, whichever of the two reasons put it that way.
    private func card(isHighlighted: Bool) -> some View {
        HStack(alignment: .bottom, spacing: ShuoSpacing.medium) {
            VStack(alignment: .leading, spacing: ShuoSpacing.small) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(isHighlighted ? ShuoColor.primaryTextAqua : ShuoColor.primaryTextCream)

                Text(description)
                    .font(ShuoTypography.caption)
                    .foregroundStyle(isHighlighted ? ShuoColor.secondaryTextAqua : ShuoColor.secondaryTextCream)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(isSelected: isHighlighted)
    }

    /// Fills the card the moment a finger lands on it, rather than only once the tap
    /// completes and something else decides to mark it selected.
    ///
    /// Unanimated on purpose. A fade in either direction is a fade the user is waiting
    /// through, and the two states hand over cleanly without one: the tap releases —
    /// clearing `isPressed` — in the same update that sets `isSelected`, so the fill never
    /// blinks between them.
    private struct Style<Card: View>: ButtonStyle {
        let isSelected: Bool
        @ViewBuilder let card: (Bool) -> Card

        func makeBody(configuration: Configuration) -> some View {
            card(isSelected || configuration.isPressed)
        }
    }
}

#Preview {
    VStack(spacing: ShuoSpacing.medium) {
        PurposeCard(
            title: "Persuade",
            description: "The act of using spoken or nonverbal messages to influence an audience's beliefs, attitudes, or behaviors to convince listeners to voluntarily adopt a new perspective or take a specific action, without using force or manipulation.",
            isSelected: true,
            action: {}
        )
        PurposeCard(
            title: "Inspire",
            description: "Motivate your audience with an emotional, memorable message.",
            isSelected: false,
            action: {}
        )
    }
    .padding()
    .background(ShuoColor.background)
}
