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
            HStack(alignment: .top, spacing: ShuoSpacing.medium) {
                VStack(alignment: .leading, spacing: ShuoSpacing.xSmall) {
                    Text(title)
                        .font(ShuoTypography.headline)
                        .foregroundStyle(ShuoColor.primaryText)
                    Text(description)
                        .font(ShuoTypography.body)
                        .foregroundStyle(ShuoColor.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? ShuoColor.accent : ShuoColor.secondaryText)
            }
            .cardStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

#Preview {
    VStack(spacing: ShuoSpacing.medium) {
        PurposeCard(
            title: "Persuade",
            description: "Convince your audience to think or act differently.",
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
}
