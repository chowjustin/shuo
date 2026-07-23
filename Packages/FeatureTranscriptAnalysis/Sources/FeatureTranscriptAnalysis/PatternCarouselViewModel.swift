//
//  PatternCarouselViewModel.swift
//  FeatureTranscriptAnalysis
//
//  Created by rasyel on 13/07/26.
//

import Foundation
import ShuoCore

/// Owns the up-to-3 suggested `SpeechPattern`s and the current selection for
/// `PatternCarouselView`.
///
/// Deliberately scoped to just the carousel — a child view model composed into
/// `TranscriptAnalysisViewModel` (CLAUDE.md §5: prefer composition over one large view
/// model). Patterns are handed in from the parent, which owns the classification call;
/// `onSelect` lets the parent react to a selection without this view model knowing about
/// AI regeneration at all.
@Observable
@MainActor
public final class PatternCarouselViewModel {

    public private(set) var patterns: [SpeechPattern]
    public private(set) var selectedPatternID: SpeechPattern.ID?

    public var onSelect: (@MainActor (SpeechPattern) -> Void)?

    public init(
        patterns: [SpeechPattern] = [],
        selectedPatternID: SpeechPattern.ID? = nil,
        onSelect: (@MainActor (SpeechPattern) -> Void)? = nil
    ) {
        self.patterns = Array(patterns.prefix(3))
        self.selectedPatternID = selectedPatternID
        self.onSelect = onSelect
    }

    public var mostRecommended: SpeechPattern? {
        patterns.first
    }

    public func isSelected(_ pattern: SpeechPattern) -> Bool {
        pattern.id == selectedPatternID
    }

    public func select(_ pattern: SpeechPattern) {
        guard pattern.id != selectedPatternID else { return }
        selectedPatternID = pattern.id
        onSelect?(pattern)
    }

    public func selectNext() {
        guard let currentID = selectedPatternID,
              let currentIndex = patterns.firstIndex(where: { $0.id == currentID }),
              currentIndex + 1 < patterns.count else { return }
        select(patterns[currentIndex + 1])
    }

    public func selectPrevious() {
        guard let currentID = selectedPatternID,
              let currentIndex = patterns.firstIndex(where: { $0.id == currentID }),
              currentIndex > 0 else { return }
        select(patterns[currentIndex - 1])
    }

    public func update(patterns: [SpeechPattern]) {
        self.patterns = Array(patterns.prefix(3))
        if let selectedPatternID, !self.patterns.contains(where: { $0.id == selectedPatternID }) {
            self.selectedPatternID = nil
        }
    }
}
