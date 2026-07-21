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
                HStack(alignment: .bottom, spacing: ShuoSpacing.medium) {
                    VStack(alignment: .leading, spacing: ShuoSpacing.small) {
                        Text(title)
                            .font(.title2.bold())
                            .foregroundStyle(ShuoColor.primaryText)
                        Text(description)
                            .font(ShuoTypography.caption)
                            .foregroundStyle(ShuoColor.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    }
