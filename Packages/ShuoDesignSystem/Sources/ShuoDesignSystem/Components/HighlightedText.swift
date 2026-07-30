//
//  HighlightedText.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

import SwiftUI

/// A `Text` that draws a colored background behind the given character ranges.
public struct HighlightedText: View {
    private let text: String
    private let highlights: [Range<Int>]
    private let highlightColor: Color
    private let textColor: Color

    /// - Parameters:
    ///   - text: The full string to render.
    ///   - highlights: Character-offset ranges within `text` to draw a background behind.
    ///   - highlightColor: The background drawn behind each highlighted range.
    ///   - textColor: The foreground color for the whole string.
    public init(
        text: String,
        highlights: [Range<Int>],
        highlightColor: Color,
        textColor: Color = .primary
    ) {
        self.text = text
        self.highlights = highlights
        self.highlightColor = highlightColor
        self.textColor = textColor
    }

    public var body: some View {
        Text(attributed)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = textColor

        let characters = attributed.characters
        let count = characters.count

        for range in highlights {
            let lower = min(max(range.lowerBound, 0), count)
            let upper = min(max(range.upperBound, lower), count)
            guard lower < upper else { continue }

            let start = characters.index(characters.startIndex, offsetBy: lower)
            let end = characters.index(characters.startIndex, offsetBy: upper)
            attributed[start ..< end].backgroundColor = highlightColor
        }
        return attributed
    }
}

#if DEBUG
    #Preview {
        HighlightedText(
            text: "We must migrate to a microservice architecture soon. The team lunch is at noon.",
            highlights: [0 ..< 52],
            highlightColor: .yellow.opacity(0.4),
            textColor: .primary
        )
        .padding()
    }
#endif
