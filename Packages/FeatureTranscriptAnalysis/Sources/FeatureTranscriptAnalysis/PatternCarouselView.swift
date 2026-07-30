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
        return Array(0 ..< (patternCount * Self.loopMultiplier))
    }

    /// The pattern shown at a looped index, or nil when there are no patterns.
    private func pattern(atLoopedIndex index: Int) -> SpeechPattern? {
        let count = viewModel.patterns.count
        guard count > 0 else { return nil }
        return viewModel.patterns[index % count]
    }

    public var body: some View {
        if viewModel.patterns.isEmpty {
            Text("No pattern suggestions yet.")
                .font(ShuoTypography.caption)
                .foregroundStyle(ShuoColor.primaryTextAqua)
                .padding(.horizontal, ShuoSpacing.medium)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                // 1. UBAH LazyHStack menjadi HStack biasa
                HStack(alignment: .center, spacing: ShuoSpacing.medium) {
                    ForEach(loopedIndices, id: \.self) { index in
                        if let currentPattern = pattern(atLoopedIndex: index) {
                            PatternCard(
                                name: currentPattern.name,
                                summary: currentPattern.summary,
                                isFocused: focusedIndex == index,
                                isMostRecommended: currentPattern.id
                                    == viewModel.mostRecommended?.id
                            )
                            .id(index)
                        }
                    }
                }
                .scrollTargetLayout()
                // 2. TAMBAHKAN padding vertikal yang lebih lega di sini
                .padding(.vertical, 32)
            }
            .safeAreaPadding(.horizontal, 60)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedIndex, anchor: .center)
            .onAppear {
                setupInitialFocus()
            }
            .onChange(of: focusedIndex) { _, newIndex in
                guard let newIndex,
                      let newPattern = pattern(atLoopedIndex: newIndex)
                else { return }
                guard newPattern.id != viewModel.selectedPatternID else {
                    return
                }
                viewModel.select(newPattern)
            }
            .onChange(of: viewModel.selectedPatternID) { _, newID in
                guard let newID,
                      let patternIdx = viewModel.patterns.firstIndex(where: {
                          $0.id == newID
                      }),
                      let current = focusedIndex,
                      current % viewModel.patterns.count != patternIdx
                else { return }
                let middleRepeat = Self.loopMultiplier / 2
                withAnimation(.none) {
                    focusedIndex =
                        middleRepeat * viewModel.patterns.count + patternIdx
                }
            }
        }
    }

    private func setupInitialFocus() {
        let patternCount = viewModel.patterns.count
        guard patternCount > 0 else { return }

        let startPatternID =
            viewModel.selectedPatternID ?? viewModel.mostRecommended?.id
        let startPatternIndex =
            startPatternID
                .flatMap { id in
                    viewModel.patterns.firstIndex(where: { $0.id == id })
                } ?? 0

        let middleRepeat = Self.loopMultiplier / 2

        withAnimation(.none) {
            focusedIndex = (middleRepeat * patternCount) + startPatternIndex
        }
    }
}

#Preview {
    PatternCarouselPreviewHost()
}

private struct PatternCarouselPreviewHost: View {
    @State private var viewModel = PatternCarouselViewModel(
        patterns: Array(
            SpeechPatternCatalog.patterns(for: .persuade).prefix(3)
        ),
        selectedPatternID: nil
    )

    var body: some View {
        PatternCarouselView(viewModel: viewModel)
            .background(ShuoColor.background)
    }
}
