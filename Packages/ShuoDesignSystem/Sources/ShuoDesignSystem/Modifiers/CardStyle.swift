//
//  CardStyle.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Shared card chrome (corner radius, shadow, padding) applied via a `ViewModifier`
// across PurposeCard/PatternCard and similar components.

import Foundation
import SwiftUI

struct CardStyle: ViewModifier {
    var isSelected: Bool = false

    private var cornerRadius: CGFloat { 20 }

    func body(content: Content) -> some View {
        content
            .padding(ShuoSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? ShuoColor.aquaTint : ShuoColor.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? ShuoColor.aqua : ShuoColor.aqua,
                        lineWidth: isSelected ? 3 : 3
                    )
            )
    }
}

extension View {
    public func cardStyle(isSelected: Bool = false) -> some View {
        modifier(CardStyle(isSelected: isSelected))
    }
}
