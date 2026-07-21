//
//  KeyPointRow.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

// One key point: its component name, and either the extracted content or a visible
// "not covered" state carrying the component's own hint.
//
// Functional only — this exists so the flow can be seen end to end. Styling and the
// editable `GhostTextField` treatment are a separate pass.

import SwiftUI
import ShuoCore

/// Renders one key point.
///
/// The absent case is deliberately *visible* rather than hidden or collapsed. Seeing which
/// components a draft does not cover is much of the value of mapping onto a fixed
/// structure — a silently shorter list would hide exactly the gap the speaker needs to
/// notice.
struct KeyPointRow: View {

    let keyPoint: KeyPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(keyPoint.componentName)
                .font(.subheadline.weight(.semibold))

            if keyPoint.isAbsent {
                Text(KeyPoint.absentText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let suggestion = keyPoint.suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(keyPoint.text)
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
