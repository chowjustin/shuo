//
//  OriginalTranscriptView.swift
//  FeatureTranscriptAnalysis
//
//  Created by rasyel on 21/07/26.
//

import ShuoDesignSystem
import SwiftUI
 
/// Shows the original transcript full-screen, editable, with its own ✕ / ✓ toolbar.
///
/// ✕ discards whatever was typed in this session and leaves the transcript untouched —
/// nothing is committed until ✓. ✓ hands the (possibly edited) text to `onSave` and
/// dismisses; an empty transcript can't be saved, since a blank original would only
/// bounce straight back as a rejected script with nothing on screen to explain why.
///
/// No script title/purpose header here — `TranscriptAnalysisView`'s `titleHeader`
/// already shows both immediately behind this sheet, so repeating them here would
/// just be the same information twice.
struct OriginalTranscriptView: View {
 
    let onSave: (String) -> Void
    let onCancel: () -> Void
 
    @State private var editedText: String
    @Environment(\.dismiss) private var dismiss
 
    init(
        originalText: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        _editedText = State(initialValue: originalText)
    }
    
    private var wordCount: Int {
        editedText.split(whereSeparator: \.isWhitespace).count
    }
 
    var body: some View {
        NavigationStack {
            ScrollView {
                transcriptCard
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(ShuoColor.background)
            .navigationTitle("Original Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDragIndicator(.visible)
    }
 
    private var transcriptCard: some View {
        editor
            .padding(ShuoSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ShuoColor.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ShuoColor.pink, lineWidth: 2)
            )
    }
 
    private var editor: some View {
        TextField("Transcript", text: $editedText, axis: .vertical)
            .font(ShuoTypography.body)
            .foregroundStyle(ShuoColor.primaryText)
            .lineLimit(1...12)
            .accessibilityLabel("Original transcript, editable")
            .accessibilityHint("Contains \(wordCount) words. Double tap to edit.")
    }
 
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
//        ToolbarItem(placement: .topBarLeading) {
//            Button {
//                onCancel()
//                dismiss()
//            } label: {
//                Image(systemName: "xmark")
//                    .font(.subheadline.weight(.semibold))
//                    .foregroundStyle(ShuoColor.primaryText)
//            }
//            .accessibilityLabel("Discard changes")
//        }
 
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onSave(editedText)
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(ShuoColor.pink)
            .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Save changes")
        }
    }
}
 
// MARK: - Preview
 
#Preview("Original Transcript") {
    OriginalTranscriptView(
        originalText: """
            Um, okay, so hi everyone. Today I kind of wanted to talk about clubs and \
            organizations on campus...
            """,
        onSave: { _ in }
    )
}
 
