//
//  ShuoColor.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Placeholder color palette. See ARCHITECTURE.md §10. Swap real brand values in here
// only — nothing else in the app touches raw colors directly.

import Foundation
import SwiftUI

public enum ShuoColor {
    public static let accent = Color(hex: 0xF7567C)
    public static let purposeTeal = Color(hex: 0x99E1D9)
    public static let background = Color(uiColor: .systemBackground)
    public static let cardBackgroundSelected = purposeTeal
    public static let cardBackgroundUnselected = purposeTeal.opacity(0.5)
    public static let cardBorderSelected = Color(hex: 0x99E1D9)
    public static let cardBorderUnselected = Color(hex: 0x99E1D9)

    public static let primaryText = Color(uiColor: .label)
    public static let secondaryText = Color(uiColor: .secondaryLabel)

    public static let closeButtonBackground = Color(uiColor: .systemGray5)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
