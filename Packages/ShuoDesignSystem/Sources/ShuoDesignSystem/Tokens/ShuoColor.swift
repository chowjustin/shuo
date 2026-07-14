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
    public static let accent = Color(red: 0.42, green: 0.36, blue: 0.91)
    public static let background = Color(uiColor: .systemBackground)
    public static let cardBackground = Color(uiColor: .secondarySystemBackground)
    public static let cardBackgroundSelected = accent.opacity(0.12)
    public static let cardBorder = Color(uiColor: .separator)
    public static let cardBorderSelected = accent
    public static let primaryText = Color(uiColor: .label)
    public static let secondaryText = Color(uiColor: .secondaryLabel)
}
