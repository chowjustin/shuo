//
//  OriginalTranscriptView.swift
//  FeatureTranscriptAnalysis
//
//  Created by rasyel on 21/07/26.
//

import ShuoDesignSystem
import SwiftUI
 
/// Shows the original transcript full-screen, editable, with its own ✕ / ✓ toolbar.
public struct OriginalTranscriptView: View {
    
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    private let originalText: String
    @State private var editedText: String
    @State private var isConfirmingSave = false
    @Environment(\.dismiss) private var dismiss
    
    public init(
        originalText: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.originalText = originalText
        self.onSave = onSave
        self.onCancel = onCancel
        _editedText = State(initialValue: originalText)
    }
    
    private var wordCount: Int {
        editedText.split(whereSeparator: \.isWhitespace).count
    }
    
    private var hasChanges: Bool {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        != originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var body: some View {
        ScrollView {
            transcriptCard
                .padding()
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ShuoColor.background)
        .navigationTitle("Original Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        
        .presentationDragIndicator(.visible)
        .alert(
            "Regenerate the analysis?",
            isPresented: $isConfirmingSave
        ) {
            Button("Save and Regenerate") {
                onSave(editedText)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving these edits will regenerate everything from your new transcript — the suggested patterns, all key points, and any refined transcripts you've generated will be replaced.")
        }
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
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if hasChanges {
                    isConfirmingSave = true
                } else {
                    dismiss()
                }
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
            .navigationBarBackButtonHidden(true)
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
 
