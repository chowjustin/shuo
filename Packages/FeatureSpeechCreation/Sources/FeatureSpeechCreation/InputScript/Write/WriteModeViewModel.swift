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

@Observable
@MainActor
public final class WriteModeViewModel {
    public var content: String = ""

    /// `true` once `content` has non-whitespace text.
    public var hasValidContent: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init() {}
}
