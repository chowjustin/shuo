//
//  WriteModeViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Nearly all logic here is the pure `content` string plus its
// trimmed-non-empty check. See ARCHITECTURE.md §3.1.4.

import Foundation
import Observation
import ShuoCore

@Observable
@MainActor
public final class WriteModeViewModel {
    public var content: String = ""

    public init() {}

    /// Whitespace alone is not content — otherwise a stray newline would enable the
    /// confirm button.
    public var hasContent: Bool {
        !trimmedContent.isEmpty
    }

    /// Typed text needs no transcription; it becomes the transcript directly
    /// (ARCHITECTURE.md §3.2.1).
    public var speechSource: SpeechSource? {
        hasContent ? .typedText(trimmedContent) : nil
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
