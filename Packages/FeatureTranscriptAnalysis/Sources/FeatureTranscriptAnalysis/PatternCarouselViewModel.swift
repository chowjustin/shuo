//
//  PatternCarouselViewModel.swift
//  FeatureTranscriptAnalysis
//
//  Created by rasyel on 13/07/26.
//

// `@Observable @MainActor`. Owns the up-to-3 suggested `SpeechPattern`s and the current
// selection for `PatternCarouselView`. Deliberately scoped to just the carousel — a
// child view model composed into `TranscriptAnalysisViewModel` (CLAUDE.md §5: prefer
// composition over one large view model). Patterns are handed in from the parent (which
// owns the `SuggestPatternsUseCase` call); `onSelect` lets the parent react to a
// selection (e.g. re-run `ApplyPatternUseCase`) without this view model knowing about
// AI regeneration at all.

import Foundation
import ShuoCore

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
        selectedPatternID = pattern.id
        onSelect?(pattern)
    }

    public func update(patterns: [SpeechPattern]) {
        self.patterns = Array(patterns.prefix(3))
        if let selectedPatternID, !self.patterns.contains(where: { $0.id == selectedPatternID }) {
            self.selectedPatternID = nil
        }
    }
}
