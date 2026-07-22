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

/// Renders one transcript with a collapsible heading and chevron toggle.
struct TranscriptSectionView: View {

    let title: String
    let text: String
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
