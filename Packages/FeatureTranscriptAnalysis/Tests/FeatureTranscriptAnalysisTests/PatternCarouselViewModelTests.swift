//
//  PatternCarouselViewModelTests.swift
//  FeatureTranscriptAnalysis
//
//  Created by rasyel on 17/07/26.
//

import Foundation
import Testing
@testable import FeatureTranscriptAnalysis
import ShuoCore

@MainActor
@Suite("PatternCarouselViewModel")
struct PatternCarouselViewModelTests {
    /// A throwaway pattern with a name-derived id. The carousel is generic over
    /// `SpeechPattern` and only reads name/summary/id, so these stay synthetic rather than
    /// pulling real catalog entries — it keeps each test's intent readable.
    private static func makePattern(_ name: String) -> SpeechPattern {
        SpeechPattern(
            id: "test.\(name)",
            name: name,
            summary: "\(name) summary",
            purpose: .inform,
            components: [
                SpeechPatternComponent(id: "only", name: "Only", contains: ["Content"], order: 0),
            ]
        )
    }

    @Test("Clamps to at most 3 patterns, preserving order")
    func clampsToThreePatterns() {
        let patterns = (1...5).map { Self.makePattern("Pattern \($0)") }
        let viewModel = PatternCarouselViewModel(patterns: patterns)

        #expect(viewModel.patterns.count == 3)
        #expect(viewModel.patterns.map(\.name) == ["Pattern 1", "Pattern 2", "Pattern 3"])
    }

    @Test("The first pattern is the most recommended, matching leftmost carousel position")
    func mostRecommendedIsFirst() {
        let patterns = [Self.makePattern("A"), Self.makePattern("B")]
        let viewModel = PatternCarouselViewModel(patterns: patterns)

        #expect(viewModel.mostRecommended == patterns[0])
    }

    @Test("Selecting a pattern updates selectedPatternID and notifies onSelect")
    func selectingUpdatesSelectionAndNotifies() {
        let patterns = [Self.makePattern("A"), Self.makePattern("B")]
        var selected: SpeechPattern?
        let viewModel = PatternCarouselViewModel(patterns: patterns, onSelect: { selected = $0 })

        viewModel.select(patterns[1])

        #expect(viewModel.selectedPatternID == patterns[1].id)
        #expect(viewModel.isSelected(patterns[1]))
        #expect(!viewModel.isSelected(patterns[0]))
        #expect(selected == patterns[1])
    }

    @Test("Updating patterns clears a selection that no longer exists")
    func updatingClearsStaleSelection() {
        let original = [Self.makePattern("A"), Self.makePattern("B")]
        let viewModel = PatternCarouselViewModel(patterns: original)
        viewModel.select(original[0])

        viewModel.update(patterns: [Self.makePattern("C"), Self.makePattern("D")])

        #expect(viewModel.selectedPatternID == nil)
        #expect(viewModel.patterns.map(\.name) == ["C", "D"])
    }

    @Test("Updating patterns keeps the selection when the pattern is still present")
    func updatingKeepsMatchingSelection() {
        let original = [Self.makePattern("A"), Self.makePattern("B")]
        let viewModel = PatternCarouselViewModel(patterns: original)
        viewModel.select(original[0])

        viewModel.update(patterns: original)

        #expect(viewModel.selectedPatternID == original[0].id)
    }
}
