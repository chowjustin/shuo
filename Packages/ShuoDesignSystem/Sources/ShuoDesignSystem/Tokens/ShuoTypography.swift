//
//  ShuoTypography.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Font style scale using Arial Rounded MT Bold (iOS system font).
// All tokens use Font.custom(_:relativeTo:) so Dynamic Type scaling is preserved.

import Foundation
import SwiftUI

public enum ShuoTypography {
    private static let fontName = "Arial Rounded MT Bold"

    public static let title = Font.custom(fontName, size: 28, relativeTo: .title).weight(.bold)
    /// A step below `title`, for content presented in a sheet rather than a screen.
    public static let sheetTitle = Font.custom(fontName, size: 20, relativeTo: .title3).weight(.bold)
    public static let headline = Font.custom(fontName, size: 17, relativeTo: .headline)
    public static let body = Font.custom(fontName, size: 17, relativeTo: .body)
    /// Supporting copy under a `sheetTitle` — larger than `caption`, quieter than `body`.
    public static let subtitle = Font.custom(fontName, size: 15, relativeTo: .subheadline)
    public static let caption = Font.custom(fontName, size: 12, relativeTo: .caption)
}
