//
//  WriteModeViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Nearly all logic here is the pure `content` string plus its
// trimmed-non-empty check. See ARCHITECTURE.md §3.1.4.

import Foundation
import Foundation

class WriteViewModel: ObservableObject {

    @Published var title: String = ""
    @Published var script: String = ""

    // Validation
    var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isScriptEmpty: Bool {
        script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Save function
    func saveScript() {
        print("Title: \(title)")
        print("Script: \(script)")

        // TODO:
        // Save to database
        // Send to API
        // Store locally
    }

    // Reset editor
    func clearAll() {
        title = ""
        script = ""
    }
}
