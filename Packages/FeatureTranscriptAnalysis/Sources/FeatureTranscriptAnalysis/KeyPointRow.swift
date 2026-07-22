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
import ShuoDesignSystem

/// Renders one key point as a labelled card: component name above, editable text inside a
/// pink-bordered card.
///
/// The absent case is deliberately *visible* rather than hidden or collapsed. Seeing which
/// components a draft does not cover is much of the value of mapping onto a fixed
/// structure — a silently shorter list would hide exactly the gap the speaker needs to
/// notice.
struct KeyPointRow: View {

    let keyPoint: KeyPoint
    let onEdit: (String) -> Void

    @State private var text: String

    init(keyPoint: KeyPoint, onEdit: @escaping (String) -> Void) {
        self.keyPoint = keyPoint
        self.onEdit = onEdit
        _text = State(initialValue: keyPoint.isAbsent ? "" : keyPoint.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(keyPoint.componentName)
                .font(.headline)
                .foregroundStyle(ShuoColor.primaryText)

            TextField(
                keyPoint.suggestion ?? "Add content for this section…",
                text: $text,
                axis: .vertical
            )
            .font(.body)
            .foregroundStyle(ShuoColor.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ShuoColor.pink, lineWidth: 1.5)
            )
            .onChange(of: text) { _, newValue in
                let stored = newValue.isEmpty ? KeyPoint.absentText : newValue
                if stored != keyPoint.text { onEdit(stored) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Reset local text when the key point content changes (pattern switch may reuse
        // the same componentID across patterns, so watch the full value not just the id)
        .onChange(of: keyPoint) { _, newKeyPoint in
            text = newKeyPoint.isAbsent ? "" : newKeyPoint.text
        }
    }
}
