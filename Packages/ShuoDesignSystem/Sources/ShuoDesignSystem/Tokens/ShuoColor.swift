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
    public static let pink = Color(hex: 0xF7567C)
    public static let pinkTint = Color(hex: 0xFFF0F4)
    public static let aqua = Color(hex: 0x99E1D9)
    public static let aquaTint = Color(hex: 0xF0FFFE)
    public static let background = Color(hex: 0xFFFDF5)
    public static let primaryTextPinkTint = Color(hex: 0x8C0030)
    public static let secondaryTextPinkTint = Color(hex: 0xC7365A)
    public static let primaryTextCream = Color(hex: 0x2c2420)
    public static let secondaryTextCream = Color(hex: 0x5D576B)

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
