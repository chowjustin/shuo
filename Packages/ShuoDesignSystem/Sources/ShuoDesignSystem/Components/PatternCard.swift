//
//  PatternCard.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Reusable card for one suggested structural pattern, shown in a horizontal
// `LazyHStack` carousel. See ARCHITECTURE.md §3.2.3.


import Foundation
import SwiftUI

public struct PatternCard: View {
    private let name: String
    private let summary: String
    private let isFocused: Bool
    private let isMostRecommended: Bool

    public init(
        name: String,
        summary: String,
        isFocused: Bool,
        isMostRecommended: Bool = false
    ) {
        self.name = name
        self.summary = summary
        self.isFocused = isFocused
        self.isMostRecommended = isMostRecommended
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            if isFocused {
                focusedContent
                    .transition(.opacity)
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .cardStyle(isSelected: true)

        .frame(width: 260)

        .scaleEffect(isFocused ? 1 : 0.85)
        .opacity(isFocused ? 1 : 0.4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
    }

    private var accessibilityText: String {
        let mainText = isFocused ? "\(name). \(summary)" : name
        return mainText
    }

    private var focusedContent: some View {
        VStack(alignment: .leading, spacing: ShuoSpacing.small) {
            Text(name)
                .font(.title3.bold())
                .foregroundStyle(ShuoColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary)
                .font(ShuoTypography.caption)
                .foregroundStyle(ShuoColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedContent: some View {
        Text(name)
            .font(ShuoTypography.headline)
            .foregroundStyle(ShuoColor.primaryText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
    }
}
