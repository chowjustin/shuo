//
//  ShuoTypography.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Font style scale: title/headline/body/caption. Placeholder type scale until real
// brand values are provided. See ARCHITECTURE.md §10.

import Foundation
import SwiftUI

public enum ShuoTypography {
    public static let title = Font.title.weight(.bold)
    /// A step below `title`, for content presented in a sheet rather than a screen.
    public static let sheetTitle = Font.title3.weight(.bold)
    public static let headline = Font.headline
    public static let body = Font.body
    /// Supporting copy under a `sheetTitle` — larger than `caption`, quieter than `body`.
    public static let subtitle = Font.subheadline
    public static let caption = Font.caption
}
