//
//  TranscriptAnalysisView.swift
//  FeatureTranscriptAnalysis
//
//  Created by Justin Chow on 13/07/26.
//

// Root view for the Transcript & pattern suggestions screen.
//
// The `.loaded` state is deliberately unstyled: it exists to make the classify → map →
// regenerate flow runnable and inspectable end to end. The designed screen —
// Original/Refined segmented control, accordions, highlight ranges (ARCHITECTURE.md §3.2)
// — is a separate pass. The loading and failure states are *not* placeholders: they share
// `LoadingView`/`ErrorSheet` and the ✕/✓ toolbar with the transcription step, because the
// user crosses from one to the other mid-flow and a change of visual language there reads
// as having landed somewhere unrelated.

import ShuoCore
import ShuoDesignSystem
import SwiftUI

/// The analysis screen.
///
/// Switches on `TranscriptAnalysisViewState` rather than on a set of booleans, so there is
/// exactly one thing on screen at a time by construction (CLAUDE.md §5).
public struct TranscriptAnalysisView: View {

    @State private var viewModel: TranscriptAnalysisViewModel
    @State private var isConfirmingLeave = false
    @State private var isShowingOriginalTranscript = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isRefinedFocused: Bool
    @State private var isRefinedExpanded = false
    private let onClose: () -> Void
    private let onBack: (ScriptDraft) -> Void

    /// - Parameter onClose: leaves the create flow entirely. Offered only once the analysis
    ///   has loaded, where ✕ means done rather than back.
    /// - Parameter onBack: returns to Input Script carrying the transcript. This is the only
    ///   control on every state *except* `.loaded` — see `toolbarContent`.
    public init(
        viewModel: TranscriptAnalysisViewModel,
        onClose: @escaping () -> Void,
        onBack: @escaping (ScriptDraft) -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onClose = onClose
        self.onBack = onBack
    }

    public var body: some View {
        NavigationStack {
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
                }
        }
        .background(ShuoColor.background)
        .task { viewModel.start() }
        // The prefetch must not outlive the screen: a background generation firing after
        // the user has dismissed this sheet is the bug class CLAUDE.md §6 calls out.
        .onDisappear { viewModel.cancelAll() }
        // Locked whenever ‹ is the only way out, since a swipe there would abandon the
        // whole create flow rather than step back. On `.loaded`, where ✕ is offered, the
        // swipe returns and is guarded only while there is unsaved work.
        .interactiveDismissDisabled(
            viewModel.viewState.toolbarLayout == .back || viewModel.hasUnsavedChanges
        )
        .confirmationDialog(
            "Leave without saving your changes?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Save and Close") { viewModel.save { _ in onClose() } }
            // Not "Discard": the analysed draft was already saved when it loaded, so what
            // is actually lost is the pattern or refinement chosen since. Naming it
            // "discard" would imply the whole speech goes, which would be a lie.
            Button("Leave", role: .destructive, action: onClose)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your speech is saved. The pattern and transcript changes you made since aren't.")
        }
    }

    // MARK: - Toolbar

    /// **Two buttons on `.loaded`, one everywhere else.**
    ///
    /// `.loaded` is the only state holding something to keep, so it is the only state that
    /// offers ✕ (leave) and ✓ (save). Every other state is a wait or a failure with nothing
    /// to confirm, and gets a single ‹ back to Input Script — the same control, in the same
    /// place, as the transcription screen the user just came from.
    ///
    /// Earlier this toolbar was unconditional, so a spinner and an error sheet both showed a
    /// ✕ and a permanently-disabled ✓. A disabled button is still a button: it invites a tap
    /// and answers with nothing, which reads as broken rather than as "not yet".
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch viewModel.viewState.toolbarLayout {
        case .leaveAndSave:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: leave) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }

        case .back:
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back to input")
            }
        }
    }

    // MARK: - Actions

    /// ✕, from `.loaded` only. Asks first when there are changes the automatic save has not
    /// captured; otherwise there is nothing to lose and a dialog would be noise.
    private func leave() {
        if viewModel.hasUnsavedChanges {
            isConfirmingLeave = true
        } else {
            onClose()
        }
    }

    /// ‹, from every state except `.loaded`.
    ///
    /// Cancels the analysis first so a generation cannot outlive the screen (CLAUDE.md §6),
    /// then hands the transcript back to Input Script. This is uniform across waiting,
    /// rejection, failure and unavailability because the recourse is identical in all four:
    /// the transcript is the thing worth keeping, and the input screen is where it can be
    /// changed or re-submitted. Re-confirming there is the retry.
    private func goBack() {
        viewModel.cancelAll()
        onBack(viewModel.draft)
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewState {
        case .analyzing:
            // The same component and copy the transcription step ends on, so crossing from
            // that sheet into this one is continuous rather than a visible handover.
            LoadingView(systemImage: "sparkles", message: "Analyzing your speech…")

        case .waitingForModel:
            // A wait, not a failure: the same `LoadingView` as `.analyzing`, differing only
            // in what it says it is waiting on (ARCHITECTURE.md §3.2.4).
            LoadingView(systemImage: "sparkles", message: "Setting up on-device AI…")

        case .unavailable(let status):
            errorSheet(AnalysisErrorCopy(availability: status))

        case .rejected(let reason):
            errorSheet(AnalysisErrorCopy(reason: reason))

        case .failed(let error):
            errorSheet(AnalysisErrorCopy(error: error))

        case .loaded:
            if viewModel.isForceRegenerating {
                LoadingView(systemImage: "sparkles", message: "Refining transcript…")
            } else {
                loadedView
            }
        }
    }

    private func errorSheet(_ copy: AnalysisErrorCopy) -> some View {
        ErrorSheet(systemImage: copy.systemImage, title: copy.title, message: copy.message)
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
                            Button { viewModel.carousel.selectPrevious() } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                    .padding(6)
                            }
                            .opacity(0)
                            Button { viewModel.carousel.selectNext() } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(6)
                            }
                            .opacity(0)
                        }
                    }
                    PatternCarouselView(viewModel: viewModel.carousel)

                    if !viewModel.carousel.patterns.isEmpty {
                        let activeIndex = viewModel.carousel.patterns.firstIndex(where: { $0.id == viewModel.carousel.selectedPatternID }) ?? 0
                        HStack(spacing: 6) {
                            ForEach(viewModel.carousel.patterns.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == activeIndex ? ShuoColor.primaryTextAqua : ShuoColor.primaryTextAqua.opacity(0.3))
                                    .frame(width: index == activeIndex ? 8 : 6, height: index == activeIndex ? 8 : 6)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: activeIndex)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                }

                KeyPointsListView(
                    keyPoints: viewModel.keyPoints,
                    isGenerating: viewModel.isGeneratingKeyPoints,
                    onEdit: { id, text in viewModel.updateKeyPoint(id: id, text: text) }
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
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if isTitleFocused { viewModel.commitTitle() }
                    isTitleFocused = false
                    isRefinedFocused = false
                }
        )
        .sheet(isPresented: $isShowingOriginalTranscript) {
            OriginalTranscriptView(
                originalText: viewModel.originalTranscript,
                onSave: { viewModel.updateOriginalTranscript($0) }
            )
        }
    }

    /// The script name and the purpose it was written for, at the top of the content.
    ///
    /// The name is editable here rather than as a bound `navigationTitle` because the input
    /// step makes it optional — a user who skipped it arrives holding "Untitled Script",
    /// and a plain field they can see and tap is a more discoverable way out of that than
    /// the nav bar's rename gesture. Styled to echo Input Script's own title field, since
    /// the user crosses directly from that screen to this one.
    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            TextField("Title", text: $viewModel.title, axis: .vertical)
                .font(ShuoTypography.title)
                .foregroundStyle(ShuoColor.primaryTextCream)
                .focused($isTitleFocused)
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
                    .background(Color(red: 222/255, green: 222/255, blue: 222/255), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Speech purpose: \(viewModel.draft.purpose.title)")

            Button {
                isShowingOriginalTranscript = true
            } label: {
                Text("View Original Transcript")
                    .underline()
            }
            .font(ShuoTypography.caption)
            .foregroundStyle(ShuoColor.pink)
        }
        .onChange(of: isTitleFocused) { _, isFocused in
            if !isFocused { viewModel.commitTitle() }
        }
    }

    private var refinedTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Refined Transcript")
                    .font(.headline)
                    .foregroundStyle(ShuoColor.primaryTextCream)

                Button("Regenerate") { viewModel.forceRegenerate() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ShuoColor.pink, in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isRefinedExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ShuoColor.primaryTextCream)
                        .rotationEffect(.degrees(isRefinedExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRefinedExpanded)
                }
                .buttonStyle(.plain)
            }

            if isRefinedExpanded {
                TextField("", text: $viewModel.editableRefinedText, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(ShuoColor.secondaryTextCream)
                    .padding(12)
                    .focused($isRefinedFocused)
                    .background(ShuoColor.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(ShuoColor.pink, lineWidth: 1.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// A failure from a pattern switch, a regeneration, or a save.
    ///
    /// At the top of the screen rather than beside the Regenerate button, because since
    /// auto-save landed the most likely error here is a *persistence* failure, which has
    /// nothing to do with regeneration — pinned next to that button it would name the wrong
    /// cause. Still inline and dismissible rather than an alert or a state change: a failed
    /// action must not tear down key points the user can still read.
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
        .background(ShuoColor.error.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
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

