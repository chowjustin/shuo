//
//  KeyPointsListView.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

import ShuoCore
import SwiftUI

/// Lists the key points for the selected pattern.
struct KeyPointsListView: View {
    let keyPoints: [KeyPoint]
    let isGenerating: Bool
    var focusedField: FocusState<AnalysisField?>.Binding
    let onEdit: (KeyPoint.ID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(keyPoints) { keyPoint in
                KeyPointRow(keyPoint: keyPoint, focusedField: focusedField) { newText in
                    onEdit(keyPoint.id, newText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
