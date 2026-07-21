//
//  TranscriptSectionView.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

// One labelled transcript block — Original or Refined.
//
// Functional only. The accordion, the Original/Refined segmented control, and key-point
// highlight ranges (ARCHITECTURE.md §3.2.2) are a separate styling pass.

import SwiftUI

/// Renders one transcript with a heading.
struct TranscriptSectionView: View {

    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
