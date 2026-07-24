// PreviewDoubles.swift
// FeatureTranscriptAnalysis
//
// Preview-only scaffolding: stand-ins for the services TranscriptAnalysisViewModel
// expects, so #Preview can build a view model without the app's composition root.
//
// Not test doubles — real ones live in ShuoTestSupport (CLAUDE.md §7). #if DEBUG
// keeps them out of release builds.
//
// Exempt from the one-type-per-file rule (CLAUDE.md §5): deleting this file breaks
// previews and nothing else.

#if DEBUG
import Foundation
import ShuoCore

// MARK: - Protocol fakes

struct PreviewAIAvailabilityChecking: AIAvailabilityChecking {
    func availability() async -> AIAvailabilityStatus { .available }
}

struct PreviewSpeechAnalyzing: SpeechAnalyzing {
    enum Behavior: Sendable {
        /// Returns scripted data immediately.
        case instant
        /// Suspends indefinitely — keeps the view in its loading state for the preview.
        case neverReturns
        /// Throws the given error on the first call.
        case failing(ShuoError)
    }

    var behavior: Behavior = .instant

    func classify(
        transcript: String,
        purpose: SpeechPurpose,
        candidates: [SpeechPattern]
    ) async throws -> PatternClassification {
        try await applyBehavior()
        let ids = Array(candidates.prefix(3).map(\.id))
        return .usable(rankedPatternIDs: ids)
    }

    func generateKeyPoints(
        transcript: String,
        pattern: SpeechPattern
    ) async throws -> [KeyPoint] {
        try await applyBehavior()
        return pattern.components.map { component in
            KeyPoint(
                componentID: component.id,
                componentName: component.name,
                text: Self.sampleText(for: component.name, in: pattern),
                orderIndex: component.order,
                suggestion: component.contains.isEmpty
                    ? nil
                    : component.contains.joined(separator: ", ")
            )
        }
    }

    func refineTranscript(
        _ transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) async throws -> String {
        try await applyBehavior()
        return """
            Every freshman here today should join a campus organization before the semester \
            is out. The reason is simple: these groups build the leadership skills, professional \
            networks, and sense of belonging that follow you long after graduation. Engineering \
            students in campus clubs report a 40% higher job-placement rate than peers who \
            didn't join. So I ask each of you to take that step this week — because joining a \
            campus organization is the single most impactful decision you can make for your future.
            """
    }

    func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion] {
        []
    }

    // MARK: - Private helpers

    private func applyBehavior() async throws {
        switch behavior {
        case .instant:
            break
        case .neverReturns:
            try await Task.sleep(for: .seconds(3_600))
        case .failing(let error):
            throw error
        }
    }

    private static func sampleText(for componentName: String, in pattern: SpeechPattern) -> String {
        let samples: [String: String] = [
            "Point": "All students should join a campus organization during their first semester.",
            "Reason": "Organizations build leadership skills, professional networks, and a sense of belonging that last long after graduation.",
            "Example": "Engineering students in campus clubs report a 40% higher job-placement rate than peers who didn't join.",
            "Reinforced Point": "Joining a campus organization is the single most impactful step a freshman can take for their future.",
            "Attention": "One in three students drops out because they feel they don't belong — yet one campus club could change everything.",
            "Need": "Students who feel disconnected are more likely to underperform and leave university before finishing.",
            "Satisfaction": "Joining a campus organization creates an instant sense of community and professional purpose.",
            "Visualization": "Imagine graduating surrounded by people who know and support your work — that network starts today.",
            "Action": "Join at least one campus organization before the end of this semester.",
            "Problem": "Many students struggle with isolation and a lack of direction during their first year.",
            "Cause": "Without structured community, students miss the peer connections that drive motivation and identity.",
            "Solution": "Campus organizations provide structured community, leadership opportunities, and career exposure.",
            "Benefits": "Members graduate with stronger networks, higher GPAs, and better employment outcomes.",
            "Challenge": "I arrived on campus knowing nobody, unsure whether I had chosen the right path.",
            "Choice": "I decided to walk into the Engineering Society meeting, even though I nearly turned back at the door.",
            "Outcome": "That decision led to my first internship, my closest friendships, and my confidence as a speaker.",
            "Beginning": "I was a shy freshman who barely spoke in class and ate lunch alone for the first three weeks.",
            "Conflict": "Every club felt too established, too intimidating — like they already had their people.",
            "Climax": "The moment I gave my first presentation at the Debate Society, something shifted inside me.",
            "Resolution": "I realized that belonging is not found — it is built, one conversation and one meeting at a time.",
            "Takeaway": "You don't need to wait until you feel ready. You become ready by showing up.",
        ]
        return samples[componentName]
            ?? "Key point for \(componentName) in the \(pattern.name) pattern."
    }
}

struct PreviewScriptRepository: ScriptRepository {
    func save(_ script: Script) async throws {}
    func fetch(id: UUID) async throws -> Script? { nil }
    func fetchSummaries() async throws -> [ScriptSummary] { [] }
    func search(query: String) async throws -> [ScriptSummary] { [] }
    func delete(id: UUID) async throws {}
}

// MARK: - ViewModel factory

extension TranscriptAnalysisViewModel {

    private static let previewTranscript = Transcript(original: """
        Joining a campus organization is the fastest way to find people who care about the same \
        things you do. The leadership skills, communication abilities, and professional networks \
        you build there follow you long after you graduate. Students who participate consistently \
        report higher academic engagement and stronger career outcomes. Engineering students in \
        campus clubs, for instance, are placed in jobs at a rate 40% higher than peers who never \
        joined. I urge every freshman here today to join at least one campus organization before \
        the end of their first semester — it is the single most impactful decision you will make.
        """)

    static func preview(
        purpose: SpeechPurpose = .persuade,
        title: String = "Why Campus Organizations Matter",
        behavior: PreviewSpeechAnalyzing.Behavior = .instant
    ) -> TranscriptAnalysisViewModel {
        let analyzer = PreviewSpeechAnalyzing(behavior: behavior)
        let draft = ScriptDraft(
            title: title,
            purpose: purpose,
            transcript: previewTranscript
        )
        return TranscriptAnalysisViewModel(
            draft: draft,
            availability: PreviewAIAvailabilityChecking(),
            classifyTranscript: ClassifyTranscriptUseCase(analyzer: analyzer),
            generateKeyPoints: GenerateKeyPointsUseCase(analyzer: analyzer),
            regenerateTranscript: RegenerateTranscriptUseCase(analyzer: analyzer),
            saveScript: SaveScriptUseCase(repository: PreviewScriptRepository())
        )
    }
}
#endif
