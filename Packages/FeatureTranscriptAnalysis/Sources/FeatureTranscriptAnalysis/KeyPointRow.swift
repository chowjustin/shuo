//
//  KeyPointRow.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

import SwiftUI
import ShuoCore
import ShuoDesignSystem

/// Renders one key point as a labelled card: component name above, editable text inside a
/// pink-bordered card.
struct KeyPointRow: View {

    let keyPoint: KeyPoint
    var focusedField: FocusState<AnalysisField?>.Binding
    let onEdit: (String) -> Void

    @State private var text: String

    init(
        keyPoint: KeyPoint,
        focusedField: FocusState<AnalysisField?>.Binding,
        onEdit: @escaping (String) -> Void
    ) {
        self.keyPoint = keyPoint
        self.focusedField = focusedField
        self.onEdit = onEdit
        _text = State(initialValue: keyPoint.isAbsent ? "" : keyPoint.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(keyPoint.componentName)
                .font(.headline)
                .foregroundStyle(ShuoColor.primaryTextCream)

            TextField(
                "Type Something",
                text: $text,
                axis: .vertical
            )
            .font(.body)
            .foregroundStyle(ShuoColor.secondaryTextCream)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .focused(focusedField, equals: .keyPoint(keyPoint.componentID))
            .background(ShuoColor.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ShuoColor.pink, lineWidth: 1.5)
            )
            .onChange(of: text) { _, newValue in
                let stored = newValue.isEmpty ? KeyPoint.absentText : newValue
                if stored != keyPoint.text { onEdit(stored) }
            }

            let isFocused = focusedField.wrappedValue == .keyPoint(keyPoint.componentID)
            if (text.isEmpty || isFocused), let suggestion = keyPoint.suggestion {
                Text(recommendedAttributed(suggestion))
                    .font(.caption)
                    .foregroundStyle(ShuoColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: keyPoint) { _, newKeyPoint in
            text = newKeyPoint.isAbsent ? "" : newKeyPoint.text
        }
    }

    private func recommendedAttributed(_ suggestion: String) -> AttributedString {
        var label = AttributedString("Recommended: ")
        label.inlinePresentationIntent = .stronglyEmphasized
        var body = AttributedString(suggestion)
        body.inlinePresentationIntent = .emphasized
        return label + body
    }
}
