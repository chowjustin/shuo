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
                .navigationTitle("Analysis")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
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
                    Text("Suggested Pattern")
                        .font(ShuoTypography.caption)
                        .foregroundStyle(ShuoColor.secondaryText)
                    PatternCarouselView(viewModel: viewModel.carousel)
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
                scriptTitle: viewModel.title,
                purposeLabel: viewModel.draft.purpose.title,
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
                .foregroundStyle(ShuoColor.primaryText)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit { viewModel.commitTitle() }
                .accessibilityLabel("Script title")

            HStack(spacing: 6) {
                Text("Purpose:")
                    .font(ShuoTypography.subtitle)
                    .foregroundStyle(ShuoColor.secondaryText)
                Text(viewModel.draft.purpose.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 4/255, green: 52/255, blue: 44/255))
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
            HStack {
                Text("Refined Transcript")
                    .font(.headline)
                Spacer()
                Button("Regenerate") { viewModel.forceRegenerate() }
                    .font(.caption)
                    .foregroundStyle(ShuoColor.pink)
            }
            TextEditor(text: $viewModel.editableRefinedText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(12)
                .focused($isRefinedFocused)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(ShuoColor.pink, lineWidth: 1.5)
                )
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

// MARK: - Preview scaffolding (not test doubles — see ShuoTestSupport)

private struct _PreviewAIAvailabilityChecking: AIAvailabilityChecking {
    func availability() async -> AIAvailabilityStatus { .available }
}

private enum _PreviewBehavior: Sendable {
    case instant, neverReturns, failing(ShuoError)
}

private struct _PreviewSpeechAnalyzing: SpeechAnalyzing {
    var behavior: _PreviewBehavior = .instant

    func classify(
        transcript: String,
        purpose: SpeechPurpose,
        candidates: [SpeechPattern]
    ) async throws -> PatternClassification {
        try await tick()
        return .usable(rankedPatternIDs: Array(candidates.prefix(3).map(\.id)))
    }

    func generateKeyPoints(
        transcript: String,
        pattern: SpeechPattern
    ) async throws -> [KeyPoint] {
        try await tick()
        return pattern.components.map { c in
            KeyPoint(
                componentID: c.id,
                componentName: c.name,
                text: _sampleText(c.name, pattern),
                orderIndex: c.order,
                suggestion: c.contains.isEmpty ? nil : c.contains.joined(separator: ", ")
            )
        }
    }

    func refineTranscript(
        _ transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) async throws -> String {
        try await tick()
        return "Every freshman here today should join a campus organization. " +
            "These groups build the leadership skills and professional networks that " +
            "follow you long after graduation. Engineering students in clubs report " +
            "a 40% higher job-placement rate. Join one before the semester is out."
    }

    func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion] { [] }

    private func tick() async throws {
        switch behavior {
        case .instant: break
        case .neverReturns: try await Task.sleep(for: .seconds(3_600))
        case .failing(let e): throw e
        }
    }
}

private func _sampleText(_ componentName: String, _ pattern: SpeechPattern) -> String {
    let map: [String: String] = [
        "Point": "All students should join a campus organization in their first semester.",
        "Reason": "Organizations build leadership skills, networks, and belonging that last long after graduation.",
        "Example": "Engineering students in clubs report a 40% higher job-placement rate.",
        "Reinforced Point": "Joining is the single most impactful step a freshman can take for their future.",
        "Attention": "One in three students drops out feeling they don't belong — yet one club could change that.",
        "Need": "Students who feel disconnected are more likely to underperform and leave before finishing.",
        "Satisfaction": "Joining a campus organization creates instant community and professional purpose.",
        "Visualization": "Imagine graduating surrounded by people who know and support your work.",
        "Action": "Join at least one campus organization before the end of this semester.",
        "Problem": "Many students struggle with isolation and lack of direction in their first year.",
        "Cause": "Without community, students miss the peer connections that drive motivation.",
        "Solution": "Campus organizations provide leadership opportunities and career exposure.",
        "Benefits": "Members graduate with stronger networks, higher GPAs, and better employment outcomes.",
        "Challenge": "I arrived on campus knowing nobody, unsure whether I'd chosen the right path.",
        "Choice": "I decided to walk into the Engineering Society meeting, even though I nearly turned back.",
        "Outcome": "That decision led to my first internship, my closest friends, and my confidence.",
        "Beginning": "I was a shy freshman who ate lunch alone for the first three weeks.",
        "Conflict": "Every club felt too established — like they already had their people.",
        "Climax": "The moment I gave my first presentation at the Debate Society, something shifted.",
        "Resolution": "I realized belonging isn't found — it's built, one conversation at a time.",
        "Takeaway": "You don't need to wait until you feel ready. You become ready by showing up.",
    ]
    return map[componentName] ?? "Key point for \(componentName) in the \(pattern.name) pattern."
}

private struct _PreviewScriptRepository: ScriptRepository {
    func save(_ script: Script) async throws {}
    func fetch(id: UUID) async throws -> Script? { nil }
    func fetchSummaries() async throws -> [ScriptSummary] { [] }
    func search(query: String) async throws -> [ScriptSummary] { [] }
}

private extension TranscriptAnalysisViewModel {
    static func previewVM(
        purpose: SpeechPurpose = .persuade,
        title: String = "Why Campus Organizations Matter",
        behavior: _PreviewBehavior = .instant
    ) -> TranscriptAnalysisViewModel {
        let analyzer = _PreviewSpeechAnalyzing(behavior: behavior)
        let draft = ScriptDraft(
            title: title,
            purpose: purpose,
            transcript: Transcript(original: """
                Joining a campus organization is the fastest way to find people who care about \
                the same things you do. The leadership skills, communication abilities, and \
                professional networks you build there follow you long after you graduate. \
                Students who participate consistently report higher academic engagement and \
                stronger career outcomes. Engineering students in campus clubs are placed in \
                jobs at a rate 40% higher than peers who never joined. I urge every freshman \
                here today to join at least one campus organization before the end of their \
                first semester — it is the single most impactful decision you will make.
                """)
        )
        return TranscriptAnalysisViewModel(
            draft: draft,
            availability: _PreviewAIAvailabilityChecking(),
            classifyTranscript: ClassifyTranscriptUseCase(analyzer: analyzer),
            generateKeyPoints: GenerateKeyPointsUseCase(analyzer: analyzer),
            regenerateTranscript: RegenerateTranscriptUseCase(analyzer: analyzer),
            saveScript: SaveScriptUseCase(repository: _PreviewScriptRepository())
        )
    }
}

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
    let behavior: _PreviewBehavior
    @State private var isPresented = true

    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                TranscriptAnalysisView(
                    viewModel: .previewVM(behavior: behavior),
                    onClose: { isPresented = false },
                    onBack: { _ in isPresented = false }
                )
            }
    }
}
#endif

