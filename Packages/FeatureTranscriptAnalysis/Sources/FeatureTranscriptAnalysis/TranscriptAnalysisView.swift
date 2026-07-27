//
//  TranscriptAnalysisView.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

import ShuoCore
import ShuoDesignSystem
import SwiftUI

/// The analysis screen.
public struct TranscriptAnalysisView: View {

    @State private var viewModel: TranscriptAnalysisViewModel
    @State private var isConfirmingLeave = false
    @State private var isConfirmingRegenerate = false
    @State private var isShowingOriginalTranscript = false  // 👈 Kembalikan variabel state ini
    @State private var pendingOriginalEdit: String?
    @FocusState private var focusedField: AnalysisField?
    @State private var isRefinedExpanded = true
    @State private var isEditingRefined = false
    private let onClose: () -> Void
    private let onBack: ((ScriptDraft) -> Void)?

    /// - Parameters:
    ///   - onClose: the user is done with this screen and with the flow behind it.
    ///   - onBack: return to Input Script, carrying the draft. `nil` when there is no
    ///     Input Script to return to — a script reopened from the library was opened
    ///     straight onto this screen — which is what hides ‹ there.
    public init(
        viewModel: TranscriptAnalysisViewModel,
        onClose: @escaping () -> Void,
        onBack: ((ScriptDraft) -> Void)? = nil
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onClose = onClose
        self.onBack = onBack
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShuoColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
                ToolbarItem(placement: .principal) {
                    Text("Script Analysis")
                        .font(.headline)
                        .foregroundStyle(ShuoColor.primaryTextCream)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: dismissKeyboard) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Done editing")
                }
            }
            .task { viewModel.start() }
            .onDisappear { viewModel.cancelAll() }
            // 👇 Ini adalah trik PUSH NATIVE untuk Original Transcript
            .navigationDestination(isPresented: $isShowingOriginalTranscript) {
                OriginalTranscriptView(
                    originalText: viewModel.originalTranscript,
                    onSave: { edited in
                        pendingOriginalEdit = edited
                        isShowingOriginalTranscript = false  // Ini otomatis memicu animasi Back Native (Pop)
                    },
                    onCancel: {
                        isShowingOriginalTranscript = false  // Memicu Back Native (Pop)
                    }
                )
            }
            .onChange(of: isShowingOriginalTranscript) { _, showing in
                if !showing, let edited = pendingOriginalEdit {
                    pendingOriginalEdit = nil
                    viewModel.updateOriginalTranscript(edited)
                }
            }

            // Mid-create-flow a swipe would tear the whole flow down rather than step back,
            // and unsaved edits are worth more than an accidental gesture either way.
            .interactiveDismissDisabled(
                controls.showsBack || viewModel.hasUnsavedChanges
            )
            .alert(
                "Leave without saving your changes?",
                isPresented: $isConfirmingLeave
            ) {
                Button("Save and Close") { viewModel.save { _ in onClose() } }
                Button("Leave", role: .destructive, action: onClose)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Your speech is saved. The pattern and transcript changes you made since aren't."
                )
            }
            .alert(
                "Some key points are still empty",
                isPresented: $isConfirmingRegenerate
            ) {
                Button("Generate Anyway") { regenerateNow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A few key points haven't been filled in yet...")
            }
            .onChange(of: isShowingOriginalTranscript) { _, showing in
                if !showing, let edited = pendingOriginalEdit {
                    pendingOriginalEdit = nil
                    viewModel.updateOriginalTranscript(edited)
                }
            }
    }

    // MARK: - Toolbar

    private var controls: AnalysisToolbarControls {
        AnalysisToolbarControls(state: viewModel.viewState, canReturnToInput: onBack != nil)
    }

    /// ‹ to step back to Input Script, ✓ to finish. Never an ✕: leaving and discarding are
    /// the same gesture here, and the prompt behind ✓ is what separates them.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if controls.showsBack {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back to input")
            }
        }

        if controls.showsFinish {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: finish) {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Done")
            }
        }
    }

    // MARK: - Actions

    /// ✓. Done with the script — but never at the cost of unsaved work, so anything
    /// outstanding is put to the user first.
    private func finish() {
        if viewModel.hasUnsavedChanges {
            isConfirmingLeave = true
        } else {
            onClose()
        }
    }

    /// ‹. Back to Input Script with the draft, leaving this screen's state intact: the
    /// user can return to it, and the recording behind it is still theirs to replay.
    private func goBack() {
        viewModel.cancelAll()
        onBack?(viewModel.draft)
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewState {
        case .analyzing:
            LoadingView(
                systemImage: "sparkles",
                message: "Analyzing your speech…"
            )

        case .waitingForModel:
            LoadingView(
                systemImage: "sparkles",
                message: "Setting up on-device AI…"
            )

        case .unavailable(let status):
            errorSheet(AnalysisErrorCopy(availability: status))

        case .rejected(let reason):
            errorSheet(AnalysisErrorCopy(reason: reason))

        case .failed(let error):
            errorSheet(AnalysisErrorCopy(error: error))

        case .loaded:
            if viewModel.isForceRegenerating {
                LoadingView(
                    systemImage: "sparkles",
                    message: "Refining transcript…"
                )
            } else {
                loadedView
            }
        }
    }

    private func errorSheet(_ copy: AnalysisErrorCopy) -> some View {
        ErrorSheet(
            systemImage: copy.systemImage,
            title: copy.title,
            message: copy.message
        )
    }

    // MARK: - Loaded view helpers

    private var loadedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = viewModel.actionError {
                    actionErrorBanner(error)
                }
                titleHeader
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Suggested Pattern")
                            .font(ShuoTypography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(ShuoColor.primaryTextCream)
                        Spacer()
                        HStack(spacing: 4) {
                            Button {
                                viewModel.carousel.selectPrevious()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                    .padding(6)
                            }
                            .opacity(0)
                            Button {
                                viewModel.carousel.selectNext()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(6)
                            }
                            .opacity(0)
                        }
                    }
                    PatternCarouselView(viewModel: viewModel.carousel)

                    if !viewModel.carousel.patterns.isEmpty {
                        let activeIndex =
                            viewModel.carousel.patterns.firstIndex(where: {
                                $0.id == viewModel.carousel.selectedPatternID
                            }) ?? 0
                        HStack(spacing: 6) {
                            ForEach(
                                viewModel.carousel.patterns.indices,
                                id: \.self
                            ) { index in
                                Circle()
                                    .fill(
                                        index == activeIndex
                                            ? ShuoColor.primaryTextAqua
                                            : ShuoColor.primaryTextAqua.opacity(
                                                0.3
                                            )
                                    )
                                    .frame(
                                        width: index == activeIndex ? 8 : 6,
                                        height: index == activeIndex ? 8 : 6
                                    )
                                    .animation(
                                        .spring(
                                            response: 0.3,
                                            dampingFraction: 0.7
                                        ),
                                        value: activeIndex
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                }

                KeyPointsListView(
                    keyPoints: viewModel.keyPoints,
                    isGenerating: viewModel.isGeneratingKeyPoints,
                    focusedField: $focusedField,
                    onEdit: { id, text in
                        viewModel.updateKeyPoint(id: id, text: text)
                    }
                )

                if viewModel.isRegeneratingTranscript {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Refining transcript…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !viewModel.editableRefinedText.isEmpty {
                    refinedTranscriptSection
                } else {
                    generateRefinedTranscriptPrompt
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
        )
    }

    private func requestRegenerate() {
        if viewModel.hasUnfulfilledKeyPoints {
            isConfirmingRegenerate = true
        } else {
            regenerateNow()
        }
    }

    /// Expands the refined-transcript section and generates it, so the result is visible the
    /// moment it lands rather than collapsed behind the chevron.
    private func regenerateNow() {
        isRefinedExpanded = true
        viewModel.forceRegenerate()
    }

    /// Resigns whichever field is focused — title, refined transcript, or any key-point card.
    private func dismissKeyboard() {
        if focusedField == .title { viewModel.commitTitle() }
        focusedField = nil
    }

    /// The script name and the purpose it was written for, at the top of the content.
    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            TextField("Title", text: $viewModel.title, axis: .vertical)
                .font(ShuoTypography.title)
                .foregroundStyle(ShuoColor.primaryTextCream)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit { viewModel.commitTitle() }
                .accessibilityLabel("Script title")

            HStack(spacing: 6) {
                Text("Purpose:")
                    .font(ShuoTypography.subtitle)
                    .foregroundStyle(ShuoColor.secondaryTextCream)
                Text(viewModel.draft.purpose.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color(
                            red: 222 / 255,
                            green: 222 / 255,
                            blue: 222 / 255
                        ),
                        in: Capsule()
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(
                "Speech purpose: \(viewModel.draft.purpose.title)"
            )

            Button {
                isShowingOriginalTranscript = true
            } label: {
                Text("View Original Transcript")
            } .underline()
        }
        .onChange(of: isShowingOriginalTranscript) { _, showing in
            if !showing,
                let edited = pendingOriginalEdit
            {

                pendingOriginalEdit = nil
                viewModel.updateOriginalTranscript(edited)
            }
        }
    }

    private var refinedTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Refined Transcript")
                    .font(.headline)
                    .foregroundStyle(ShuoColor.primaryTextCream)

                Button("Regenerate") { requestRegenerate() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        ShuoColor.pink,
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8))
                    {
                        isRefinedExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ShuoColor.primaryTextCream)
                        .rotationEffect(.degrees(isRefinedExpanded ? 180 : 0))
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.8),
                            value: isRefinedExpanded
                        )
                }
                .buttonStyle(.plain)
            }

            if isRefinedExpanded {
                refinedTranscriptBody

                if !isEditingRefined, !viewModel.refinedHighlightRanges.isEmpty
                {
                    Label(
                        "Highlighted text matches your key points.",
                        systemImage: "highlighter"
                    )
                    .font(.caption2)
                    .foregroundStyle(ShuoColor.secondaryText)
                }
            }
        }
        // Editing ends when focus leaves the field — via the keyboard bar or a tap elsewhere —
        // so the highlighted view returns without a dedicated Done control.
        .onChange(of: focusedField) { _, newValue in
            if newValue != .refined { isEditingRefined = false }
        }
    }

    @ViewBuilder
    private var refinedTranscriptBody: some View {
        if isEditingRefined {
            TextField("", text: $viewModel.editableRefinedText, axis: .vertical)
                .font(.body)
                .foregroundStyle(ShuoColor.secondaryTextCream)
                .padding(16)
                .focused($focusedField, equals: .refined)
                .background(
                    ShuoColor.background,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(ShuoColor.pink, lineWidth: 1.5)
                )
                .onAppear { focusedField = .refined }
        } else {
            HighlightedText(
                text: viewModel.editableRefinedText,
                highlights: viewModel.refinedHighlightRanges,
                highlightColor: ShuoColor.pink.opacity(0.35),
                textColor: ShuoColor.secondaryTextCream
            )
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                ShuoColor.background,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ShuoColor.pink, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .onTapGesture { isEditingRefined = true }
        }
    }

    /// Shown for a selected pattern that has no refined transcript yet — a pattern the user
    /// switched to but hasn't generated a refinement for.
    private var generateRefinedTranscriptPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refined Transcript")
                .font(.headline)
                .foregroundStyle(ShuoColor.primaryTextCream)

            Text(
                "Generate a rewritten version of your speech, structured to this pattern and built from your key points."
            )
            .font(.caption)
            .foregroundStyle(ShuoColor.secondaryTextCream)
            .fixedSize(horizontal: false, vertical: true)

            Button("Generate Refined Transcript") { requestRegenerate() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ShuoColor.pink,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A failure from a pattern switch, a regeneration, or a save.
    private func actionErrorBanner(_ error: ShuoError) -> some View {
        let copy = AnalysisErrorCopy(error: error)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: copy.systemImage)
                .foregroundStyle(ShuoColor.error)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(copy.title)
                    .font(.subheadline.weight(.semibold))
                Text(copy.message)
                    .font(.caption)
                    .foregroundStyle(ShuoColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss") { viewModel.dismissActionError() }
                .font(.caption)
        }
        .padding(12)
        .background(
            ShuoColor.error.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

}

#if DEBUG

    // MARK: - Previews (doubles live in PreviewDoubles.swift)

    #Preview("Loaded") {
        _AnalysisPreviewHost(behavior: .instant)
    }

    #Preview("Analyzing") {
        _AnalysisPreviewHost(behavior: .neverReturns)
    }

    #Preview("Failed") {
        _AnalysisPreviewHost(behavior: .failing(.aiGenerationFailed))
    }

    private struct _AnalysisPreviewHost: View {
        let behavior: PreviewSpeechAnalyzing.Behavior
        @State private var isPresented = true

        var body: some View {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .sheet(isPresented: $isPresented) {
                    TranscriptAnalysisView(
                        viewModel: .preview(behavior: behavior),
                        onClose: { isPresented = false },
                        onBack: { _ in isPresented = false }
                    )
                }
        }
    }
#endif
