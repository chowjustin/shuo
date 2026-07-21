//
//  KeyPointsListView.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

// The key points for the selected pattern, in component order.
//
// Functional only — styling is a separate pass.

import SwiftUI
import ShuoCore

/// Lists the key points for the selected pattern.
///
/// Renders positionally with no gap handling, which it can do because
/// `KeyPointNormalizer` guarantees one key point per component in order — including the
/// absent ones.
struct KeyPointsListView: View {

    let keyPoints: [KeyPoint]
    let isGenerating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Key Points")
                    .font(.headline)
                if isGenerating {
                    // An in-place indicator, not a screen transition — switching patterns
                    // must not flash the whole screen back to a spinner.
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(keyPoints) { keyPoint in
                KeyPointRow(keyPoint: keyPoint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
