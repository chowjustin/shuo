//
//  PatternCarouselView.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore
import ShuoDesignSystem
import SwiftUI

public struct PatternCarouselView: View {
    private static let loopMultiplier = 20
    private let viewModel: PatternCarouselViewModel
    @State private var focusedIndex: Int?

    public init(viewModel: PatternCarouselViewModel) {
        self.viewModel = viewModel
    }

    private var loopedIndices: [Int] {
        let patternCount = viewModel.patterns.count
        guard patternCount > 0 else { return [] }
        return Array(0..<(patternCount * Self.loopMultiplier))
    }

    private func pattern(atLoopedIndex index: Int) -> SpeechPattern {
        viewModel.patterns[index % viewModel.patterns.count]
    }

    public var body: some View {
        if viewModel.patterns.isEmpty {
            Text("No pattern suggestions yet.")
                .font(ShuoTypography.caption)
                .foregroundStyle(ShuoColor.secondaryText)
                .padding(.horizontal, ShuoSpacing.medium)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: ShuoSpacing.medium) {
                    ForEach(loopedIndices, id: \.self) { index in
                        let currentPattern = pattern(atLoopedIndex: index)
                        PatternCard(
                            name: currentPattern.name,
                            summary: currentPattern.summary,
                            isFocused: focusedIndex == index,
                            isMostRecommended: currentPattern.id == viewModel.mostRecommended?.id
                        )
                        .id(index)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, ShuoSpacing.small)
            }
            .safeAreaPadding(.horizontal, 60)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedIndex, anchor: .center)
        
            .onAppear {
                setupInitialFocus()
            }
            .onChange(of: focusedIndex) { _, newIndex in
                guard let newIndex else { return }
                viewModel.select(pattern(atLoopedIndex: newIndex))
            }
        }
    }

    private func setupInitialFocus() {
        let patternCount = viewModel.patterns.count
        guard patternCount > 0 else { return }

        let startPatternID = viewModel.selectedPatternID ?? viewModel.mostRecommended?.id
        let startPatternIndex = startPatternID
            .flatMap { id in viewModel.patterns.firstIndex(where: { $0.id == id }) } ?? 0
        
        let middleRepeat = Self.loopMultiplier / 2

        focusedIndex = (middleRepeat * patternCount) + startPatternIndex
    }
}

#Preview {
    PatternCarouselPreviewHost()
}

private struct PatternCarouselPreviewHost: View {
    // Real catalog entries rather than invented ones: patterns are fixed app data now, so
    // the preview shows exactly what ships (see `SpeechPatternCatalog`).
    @State private var viewModel = PatternCarouselViewModel(
        patterns: Array(SpeechPatternCatalog.patterns(for: .persuade).prefix(3)),
        selectedPatternID: nil
    )

    var body: some View {
        PatternCarouselView(viewModel: viewModel)
            .background(ShuoColor.background)
    }
}
