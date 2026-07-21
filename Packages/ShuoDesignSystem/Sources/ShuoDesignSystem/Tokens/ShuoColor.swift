//
//  ShuoColor.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// All colors sourced from Assets.xcassets in this package — dark mode, light mode,
// and high contrast variants are defined there. Never use raw Color(hex:) or
// hardcoded UIColor values outside this file.

import Foundation
import SwiftUI

public enum ShuoColor {
    // MARK: - Base brand colors (Tile context — matches legacy hex values)

    /// Primary brand pink, used on interactive elements and highlights.
    public static let pink = Color("Color/Tile/Pink", bundle: .module)
    public static let pinkTint = Color("Color/Tile/PinkTint", bundle: .module)
    public static let aqua = Color("Color/Tile/Aqua", bundle: .module)
    public static let aquaTint = Color("Color/Tile/AquaTint", bundle: .module)
    /// App background surface color.
    public static let background = Color("Color/Tile/Base", bundle: .module)

    // MARK: - Contextual text colors for ScriptCard selected/unselected states

    /// Primary text on pink-tint (selected card) background.
    public static let primaryTextPinkTint = Color("Color/Title/PinkTint", bundle: .module)
    /// Secondary text on pink-tint (selected card) background.
    public static let secondaryTextPinkTint = Color("Color/Title/SecondaryPinkTint", bundle: .module)
    /// Primary text on cream (unselected card) background.
    public static let primaryTextCream = Color("Color/Title/Base", bundle: .module)
    /// Secondary text on cream (unselected card) background.
    public static let secondaryTextCream = Color("Color/Title/SecondaryBase", bundle: .module)

    // MARK: - System adaptive colors

    public static let primaryText = Color(uiColor: .label)
    public static let secondaryText = Color(uiColor: .secondaryLabel)
    public static let closeButtonBackground = Color(uiColor: .systemGray5)
    /// Failure states — error sheet glyphs and destructive emphasis.
    public static let error = Color(uiColor: .systemRed)
    /// Surface for content presented above the app, e.g. a sheet background.
    public static let elevatedSurface = Color(uiColor: .systemBackground)

    // MARK: - Contextual color tokens

    /// Colors for body/content areas.
    public enum Body {
        public static let aqua = Color("Color/Body/Aqua", bundle: .module)
        public static let aquaTint = Color("Color/Body/AquaTint", bundle: .module)
        public static let base = Color("Color/Body/Base", bundle: .module)
        public static let card = Color("Color/Body/Card", bundle: .module)
        public static let pink = Color("Color/Body/Pink", bundle: .module)
        public static let pinkTint = Color("Color/Body/PinkTint", bundle: .module)
    }

    /// Colors for tile/card surfaces.
    public enum Tile {
        public static let aqua = Color("Color/Tile/Aqua", bundle: .module)
        public static let aquaTint = Color("Color/Tile/AquaTint", bundle: .module)
        public static let base = Color("Color/Tile/Base", bundle: .module)
        public static let card = Color("Color/Tile/Card", bundle: .module)
        public static let pink = Color("Color/Tile/Pink", bundle: .module)
        public static let pinkTint = Color("Color/Tile/PinkTint", bundle: .module)
    }

    /// Colors for title/heading text.
    public enum Title {
        public static let aqua = Color("Color/Title/Aqua", bundle: .module)
        public static let aquaTint = Color("Color/Title/AquaTint", bundle: .module)
        public static let base = Color("Color/Title/Base", bundle: .module)
        public static let card = Color("Color/Title/Card", bundle: .module)
        public static let pink = Color("Color/Title/Pink", bundle: .module)
        public static let pinkTint = Color("Color/Title/PinkTint", bundle: .module)
    }
}
