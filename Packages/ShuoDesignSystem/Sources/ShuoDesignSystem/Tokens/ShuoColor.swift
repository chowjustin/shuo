//
//  ShuoColor.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// The brand palette, resolved from this package's asset catalog. See ARCHITECTURE.md §10.
// Nothing else in the app touches raw colors directly.

import Foundation
import SwiftUI

/// Every color in the app, as a semantic token.
///
/// **Surface plus on-surface text.** Six surfaces, each with a title (primary) and body
/// (secondary) color authored to sit on it. Pick the surface first, then take its text
/// colors from the same family — `pinkTint` with `primaryTextPinkTint`, never with
/// `primaryTextCream`. Contrast was checked per pair, so mixing families is what breaks it.
///
/// **Every token adapts.** Each color set carries four appearances: light, dark, and an
/// increased-contrast variant of each. Resolution happens at render time, so no call site
/// needs to branch on appearance and no literal hex belongs outside the catalog.
public enum ShuoColor {

    // MARK: - Surfaces

    /// The app background: soft cream in light, warm near-black in dark.
    public static let background = tile("Base")
    /// Content raised off the background. In increased-contrast light this deliberately
    /// matches `background`; separate it with a warm border there rather than a fill.
    public static let card = tile("Card")
    /// Aqua fill — confirmed pattern sections and confirm buttons.
    public static let aqua = tile("Aqua")
    /// The low-chroma aqua surface — inactive pattern options and filled sections.
    public static let aquaTint = tile("AquaTint")
    /// Pink fill — the primary accent surface.
    public static let pink = tile("Pink")
    /// The low-chroma pink surface — pattern label cards.
    public static let pinkTint = tile("PinkTint")

    // MARK: - Title (primary) text, by surface

    public static let primaryTextCream = title("Base")
    public static let primaryTextCard = title("Card")
    public static let primaryTextAqua = title("Aqua")
    public static let primaryTextAquaTint = title("AquaTint")
    public static let primaryTextPink = title("Pink")
    public static let primaryTextPinkTint = title("PinkTint")

    // MARK: - Body (secondary) text, by surface

    public static let secondaryTextCream = body("Base")
    public static let secondaryTextCard = body("Card")
    public static let secondaryTextAqua = body("Aqua")
    public static let secondaryTextAquaTint = body("AquaTint")
    public static let secondaryTextPink = body("Pink")
    public static let secondaryTextPinkTint = body("PinkTint")

    // MARK: - Standalone

    /// Muted hint text in empty fields. Deliberately below AA in the default appearances —
    /// it is a hint, never content — and raised toward body contrast in increased contrast.
    public static let placeholderText = named("Placeholder")

    // MARK: - System-derived
    //
    // Already adapt to appearance and contrast on their own, so they stay system colors
    // rather than being re-authored in the catalog.

    public static let primaryText = Color(uiColor: .label)
    public static let secondaryText = Color(uiColor: .secondaryLabel)
    public static let closeButtonBackground = Color(uiColor: .systemGray5)
    /// Failure states — error sheet glyphs and destructive emphasis.
    public static let error = Color(uiColor: .systemRed)
    /// Surface for content presented above the app, e.g. a sheet background.
    public static let elevatedSurface = Color(uiColor: .systemBackground)

    // MARK: - Resolution

    private static func tile(_ name: String) -> Color { named("Tile/\(name)") }
    private static func title(_ name: String) -> Color { named("Title/\(name)") }
    private static func body(_ name: String) -> Color { named("Body/\(name)") }

    /// Resolves against this package's bundle, so previews find the catalog too.
    private static func named(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}
