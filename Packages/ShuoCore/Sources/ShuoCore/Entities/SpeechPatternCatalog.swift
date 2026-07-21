//
//  SpeechPatternCatalog.swift
//  ShuoCore
//

// The fixed, closed set of speech structure patterns. Transcribed from
// `Docs/SPEECH_PATTERNS.md`, which is the human-readable source of truth — if the two
// ever disagree, that document wins and this file is the bug.
//
// The model never invents patterns; it only classifies a transcript against the entries
// here and maps content onto their components. See `SpeechPattern` for why that changed
// from the original `Docs/ARCHITECTURE.md` §3.2.4 design.
//
// Style note: every entry is its own explicitly-typed `static let` built from the `comp`
// helper rather than one big nested literal. That is not cosmetic — a single array
// literal holding 23 patterns' worth of nested arrays and optionals blows up Swift's
// type checker ("unable to type-check this expression in reasonable time"). Concrete
// return types and one declaration per pattern keep inference trivial.

import Foundation

/// Every speech structure pattern the app knows about, grouped by purpose.
///
/// 23 entries across three purposes. Cause-Effect and Chronological each appear under two
/// purposes as *separate entries with distinct ids* rather than one entry tagged twice:
/// their guidance text genuinely differs, and separate ids keep every classification
/// prompt scoped to a single purpose with no conditional wording.
public enum SpeechPatternCatalog {

    /// Every pattern, in purpose order. Order within a purpose is the authoring order in
    /// `Docs/SPEECH_PATTERNS.md` and carries no ranking meaning — ranking is the model's
    /// job, per transcript.
    public static let all: [SpeechPattern] = inform + persuade + inspire

    /// The patterns offered for a given purpose. This is the candidate set handed to
    /// classification; a transcript is never matched against a pattern from another
    /// purpose.
    public static func patterns(for purpose: SpeechPurpose) -> [SpeechPattern] {
        switch purpose {
        case .inform: inform
        case .persuade: persuade
        case .inspire: inspire
        }
    }

    /// Lookup by stable slug. Returns nil for an unknown id, which is how a hallucinated
    /// identifier from the model gets rejected rather than propagated.
    public static func pattern(id: SpeechPattern.ID) -> SpeechPattern? {
        all.first { $0.id == id }
    }

    /// Resolves a ranked list of ids to patterns, preserving the given order and silently
    /// dropping ids that are not in the catalog.
    public static func patterns(ids: [SpeechPattern.ID]) -> [SpeechPattern] {
        ids.compactMap(pattern(id:))
    }

    // MARK: - To Inform

    static let inform: [SpeechPattern] = [
        informTopical,
        informChronological,
        informCauseEffect,
        informSequential,
        informSpatial,
        informDefinition,
        informClassification,
        informComparisonContrast,
    ]

    private static let informTopical: SpeechPattern = make(
        id: "inform.topical",
        name: "Topical (Categorical)",
        summary: "Organizes information into categories or major aspects of the topic.",
        purpose: .inform,
        source: lucas,
        components: [
            comp("topicOverview", "Topic Overview",
                 ["Main subject", "Brief introduction", "Scope of discussion"],
                 "Extract the overall topic and explain what will be discussed."),
            comp("category1", "Category 1",
                 ["First major aspect", "Supporting explanation", "Facts/examples"],
                 "Identify the first independent category that explains the topic."),
            comp("category2", "Category 2",
                 ["Second major aspect", "Supporting explanation", "Facts/examples"]),
            comp("category3", "Category 3",
                 ["Third major aspect", "Supporting explanation"]),
            comp("closingSummary", "Closing Summary",
                 ["Recap of categories", "Final takeaway"]),
        ]
    )

    private static let informChronological: SpeechPattern = make(
        id: "inform.chronological",
        name: "Chronological",
        summary: "Presents information according to time order.",
        purpose: .inform,
        source: lucas,
        components: [
            comp("beginning", "Beginning",
                 ["Starting event", "Initial situation"],
                 "Find the earliest event."),
            comp("middle", "Middle", ["Sequence of developments", "Progression"]),
            comp("end", "End", ["Final event", "Result"]),
            comp("takeaway", "Takeaway", ["Overall timeline summary"]),
        ]
    )

    private static let informCauseEffect: SpeechPattern = make(
        id: "inform.causeEffect",
        name: "Cause-Effect",
        summary: "Explains why something happened and what followed from it.",
        purpose: .inform,
        source: oklahomaState,
        components: [
            comp("cause", "Cause",
                 ["Root causes", "Contributing factors"],
                 "Identify WHY something happened."),
            comp("effects", "Effects",
                 ["Immediate impacts", "Long-term impacts"],
                 "Identify WHAT happened because of the causes."),
            comp("conclusion", "Conclusion", ["Overall implication"]),
        ]
    )

    private static let informSequential: SpeechPattern = make(
        id: "inform.sequential",
        name: "Sequential (Process)",
        summary: "Walks through a process step by step toward an outcome.",
        purpose: .inform,
        source: lucas,
        components: [
            comp("goal", "Goal", ["Desired outcome"]),
            comp("step1", "Step 1", ["First action"]),
            comp("step2", "Step 2", ["Second action"]),
            comp("step3", "Step 3", ["Remaining actions"]),
            comp("expectedResult", "Expected Result", ["Final outcome"]),
        ]
    )

    private static let informSpatial: SpeechPattern = make(
        id: "inform.spatial",
        name: "Spatial",
        summary: "Organizes information by physical location or arrangement.",
        purpose: .inform,
        source: lucas,
        components: [
            comp("overallSubject", "Overall Subject", ["Object/place overview"]),
            comp("area1", "Area 1", ["Description", "Importance"]),
            comp("area2", "Area 2", ["Description", "Importance"]),
            comp("area3", "Area 3", ["Description", "Importance"]),
            comp("overallUnderstanding", "Overall Understanding",
                 ["Relationship between locations"]),
        ]
    )

    private static let informDefinition: SpeechPattern = make(
        id: "inform.definition",
        name: "Definition",
        summary: "Explains what something is and why it matters.",
        purpose: .inform,
        source: nil,
        components: [
            comp("definition", "Definition", ["Formal definition"]),
            comp("characteristics", "Characteristics", ["Key attributes"]),
            comp("examples", "Examples", ["Illustrations"]),
            comp("importance", "Importance", ["Why the audience should understand it"]),
        ]
    )

    private static let informClassification: SpeechPattern = make(
        id: "inform.classification",
        name: "Classification",
        summary: "Sorts a subject into categories by criteria.",
        purpose: .inform,
        source: nil,
        components: [
            comp("mainTopic", "Main Topic", ["Object being classified"]),
            comp("categoryA", "Category A", ["Criteria", "Explanation"]),
            comp("categoryB", "Category B", ["Criteria", "Explanation"]),
            comp("comparisonSummary", "Comparison Summary",
                 ["Differences among categories"]),
        ]
    )

    private static let informComparisonContrast: SpeechPattern = make(
        id: "inform.comparisonContrast",
        name: "Comparison / Contrast",
        summary: "Sets two subjects side by side.",
        purpose: .inform,
        source: nil,
        components: [
            comp("subjectA", "Subject A", ["Key features"]),
            comp("subjectB", "Subject B", ["Key features"]),
            comp("similarities", "Similarities", ["Shared characteristics"]),
            comp("differences", "Differences", ["Contrasting characteristics"]),
            comp("conclusion", "Conclusion", ["Main insight"]),
        ]
    )

    // MARK: - To Persuade

    static let persuade: [SpeechPattern] = [
        persuadePREP,
        persuadeMonroe,
        persuadeProblemCauseSolution,
        persuadeComparativeAdvantages,
        persuadeCauseEffect,
        persuadeRefutation,
        persuadeCER,
    ]

    private static let persuadePREP: SpeechPattern = make(
        id: "persuade.prep",
        name: "PREP",
        summary: "Claim, justification, evidence, restated claim.",
        purpose: .persuade,
        source: "PREP Method (Japanese business communication); Dale Carnegie Training; Barbara Minto, The Pyramid Principle",
        components: [
            comp("point", "Point",
                 ["One clear claim or recommendation",
                  "The speaker's stance",
                  "The central persuasive message"],
                 "Extract the main opinion or recommendation as one concise sentence."),
            comp("reason", "Reason",
                 ["Logical justification",
                  "Benefits/rationale",
                  "Why the audience should believe the claim"],
                 "Identify the strongest supporting reason directly connected to the point."),
            comp("example", "Example",
                 ["Personal experience", "Real-world example", "Statistics",
                  "Research findings", "Case study"],
                 "Extract the most convincing evidence that supports the reason."),
            comp("reinforcedPoint", "Reinforced Point",
                 ["Restated claim", "Strong call-to-action or memorable closing"],
                 "Rewrite the original point as a stronger concluding statement that reinforces the desired action."),
        ]
    )

    private static let persuadeMonroe: SpeechPattern = make(
        id: "persuade.monroe",
        name: "Monroe's Motivated Sequence",
        summary: "Moves an audience from attention to action in five stages.",
        purpose: .persuade,
        source: "Alan Monroe (1935)",
        components: [
            comp("attention", "Attention",
                 ["Hook", "Problem introduction", "Surprising fact", "Question"]),
            comp("need", "Need",
                 ["Problem explanation", "Why the audience should care"]),
            comp("satisfaction", "Satisfaction", ["Proposed solution"]),
            comp("visualization", "Visualization",
                 ["The future if the solution is adopted (or ignored)"]),
            comp("action", "Action", ["Clear call to action"]),
        ]
    )

    private static let persuadeProblemCauseSolution: SpeechPattern = make(
        id: "persuade.problemCauseSolution",
        name: "Problem-Cause-Solution",
        summary: "Names a problem, traces its cause, then proposes a fix.",
        purpose: .persuade,
        source: nil,
        components: [
            comp("problem", "Problem", ["Current issue"]),
            comp("cause", "Cause", ["Root causes"]),
            comp("solution", "Solution", ["Proposed solution"]),
            comp("benefits", "Benefits", ["Expected outcomes"]),
        ]
    )

    private static let persuadeComparativeAdvantages: SpeechPattern = make(
        id: "persuade.comparativeAdvantages",
        name: "Comparative Advantages",
        summary: "Argues for one option by weighing it against the alternatives.",
        purpose: .persuade,
        source: nil,
        components: [
            comp("option", "Option", ["Recommended choice"]),
            comp("alternative", "Alternative", ["Other choices"]),
            comp("comparison", "Comparison", ["Strengths and weaknesses"]),
            comp("recommendation", "Recommendation",
                 ["Why the recommended option is best"]),
        ]
    )

    private static let persuadeCauseEffect: SpeechPattern = make(
        id: "persuade.causeEffect",
        name: "Cause-Effect (persuasive)",
        summary: "Traces causes to effects, closing on what the audience should do about it.",
        purpose: .persuade,
        source: oklahomaState,
        components: [
            comp("cause", "Cause",
                 ["Root causes", "Contributing factors"],
                 "Identify WHY something happened."),
            comp("effects", "Effects",
                 ["Immediate impacts", "Long-term impacts"],
                 "Identify WHAT happened because of the causes."),
            comp("conclusion", "Conclusion",
                 ["Persuasive implication", "Recommended action"],
                 "State what the audience should conclude or do."),
        ]
    )

    private static let persuadeRefutation: SpeechPattern = make(
        id: "persuade.refutation",
        name: "Refutation",
        summary: "States an opposing view, dismantles it, and establishes a stronger position.",
        purpose: .persuade,
        source: nil,
        components: [
            comp("claim", "Claim", ["Opposing viewpoint"]),
            comp("counterargument", "Counterargument",
                 ["Weaknesses", "Missing evidence"]),
            comp("evidence", "Evidence", ["Supporting evidence for the rebuttal"]),
            comp("conclusion", "Conclusion", ["Stronger position"]),
        ]
    )

    private static let persuadeCER: SpeechPattern = make(
        id: "persuade.cer",
        name: "Claim-Evidence-Reasoning (CER)",
        summary: "Backs a claim with evidence, then explains why the evidence supports it.",
        purpose: .persuade,
        source: "McNeill & Krajcik (2012), Supporting Grade 5–8 Students in Constructing Explanations in Science; NGSS Evidence-Based Reasoning Framework",
        components: [
            comp("claim", "Claim", ["Main argument"]),
            comp("evidence", "Evidence", ["Facts", "Statistics", "Examples"]),
            comp("reasoning", "Reasoning",
                 ["Explanation of how the evidence supports the claim"]),
        ]
    )

    // MARK: - To Inspire

    static let inspire: [SpeechPattern] = [
        inspireChallengeChoiceOutcome,
        inspireNarrativeArc,
        inspirePublicNarrative,
        inspireHerosJourney,
        inspirePersonalStory,
        inspireProblemSolution,
        inspireBeforeAfterBridge,
        inspireChronological,
    ]

    private static let inspireChallengeChoiceOutcome: SpeechPattern = make(
        id: "inspire.challengeChoiceOutcome",
        name: "Challenge–Choice–Outcome",
        summary: "Frames a defining moment, the decision it forced, and what came of it.",
        purpose: .inspire,
        source: "Leadership storytelling frameworks (leadership development, behavioral interviews)",
        components: [
            comp("challenge", "Challenge",
                 ["The obstacle, setback, or defining moment that created tension or required action"]),
            comp("choice", "Choice",
                 ["The decision, mindset, or action taken to address the challenge"]),
            comp("outcome", "Outcome",
                 ["The result, lesson learned, or positive transformation that inspires the audience"]),
        ]
    )

    private static let inspireNarrativeArc: SpeechPattern = make(
        id: "inspire.narrativeArc",
        name: "Narrative / Storytelling Arc",
        summary: "Builds a story from setup through conflict and climax to a lesson.",
        purpose: .inspire,
        source: "Freytag's Pyramid; Nancy Duarte, Resonate",
        components: [
            comp("beginning", "Beginning", ["Setting, context, and characters"]),
            comp("conflict", "Conflict", ["The central challenge or tension"]),
            comp("climax", "Climax", ["The turning point or decisive moment"]),
            comp("resolution", "Resolution", ["How the situation was resolved"]),
            comp("takeaway", "Takeaway", ["The lesson or message for the audience"]),
        ]
    )

    private static let inspirePublicNarrative: SpeechPattern = make(
        id: "inspire.publicNarrative",
        name: "Public Narrative (Marshall Ganz)",
        summary: "Links a personal story to shared values and an urgent call to act together.",
        purpose: .inspire,
        source: "Marshall Ganz, Harvard Kennedy School",
        components: [
            comp("storyOfSelf", "Story of Self",
                 ["Why this issue matters personally to the speaker"]),
            comp("storyOfUs", "Story of Us",
                 ["Connection from the personal story to shared values or experiences"]),
            comp("storyOfNow", "Story of Now",
                 ["The urgency", "Inspiring immediate collective action"]),
        ]
    )

    private static let inspireHerosJourney: SpeechPattern = make(
        id: "inspire.herosJourney",
        name: "Hero's Journey",
        summary: "Follows a transformation from an ordinary world through trials to a message.",
        purpose: .inspire,
        source: "Joseph Campbell, The Hero with a Thousand Faces",
        components: [
            comp("ordinaryWorld", "Ordinary World", ["Initial situation before change"]),
            comp("callToAdventure", "Challenge / Call to Adventure",
                 ["The event that initiates change"]),
            comp("trials", "Trials", ["Obstacles and growth throughout the journey"]),
            comp("transformation", "Transformation",
                 ["The key insight or personal change achieved"]),
            comp("returnMessage", "Return / Message",
                 ["The lesson shared", "How it inspires the audience"]),
        ]
    )

    private static let inspirePersonalStory: SpeechPattern = make(
        id: "inspire.personalStory",
        name: "Personal Story",
        summary: "Recounts a lived experience and applies its lesson to the audience.",
        purpose: .inspire,
        source: "Annette Simmons, Whoever Tells the Best Story Wins",
        components: [
            comp("situation", "Situation", ["The context"]),
            comp("experience", "Experience", ["What happened"]),
            comp("reflection", "Reflection", ["What was learned"]),
            comp("application", "Application",
                 ["How the lesson connects to the audience"]),
        ]
    )

    private static let inspireProblemSolution: SpeechPattern = make(
        id: "inspire.problemSolution",
        name: "Problem–Solution",
        summary: "Raises a problem that resonates, then the action that changed it.",
        purpose: .inspire,
        source: nil,
        components: [
            comp("problem", "Problem",
                 ["An issue that resonates emotionally with the audience"]),
            comp("solution", "Solution",
                 ["The action or idea that addressed the problem"]),
            comp("impact", "Impact", ["The positive change created"]),
            comp("inspiration", "Inspiration",
                 ["Encouragement to take a similar perspective or action"]),
        ]
    )

    private static let inspireBeforeAfterBridge: SpeechPattern = make(
        id: "inspire.beforeAfterBridge",
        name: "Before–After–Bridge (BAB)",
        summary: "Contrasts today's pain with a better future, then bridges the gap.",
        purpose: .inspire,
        source: "Popularized in copywriting by Buffer and other marketing practitioners",
        components: [
            comp("before", "Before", ["The current reality or pain point"]),
            comp("after", "After", ["A vivid picture of the desired future state"]),
            comp("bridge", "Bridge",
                 ["How to move from the current state to the desired future"]),
        ]
    )

    private static let inspireChronological: SpeechPattern = make(
        id: "inspire.chronological",
        name: "Chronological (inspirational)",
        summary: "Traces a journey through milestones to a turning point and a lesson.",
        purpose: .inspire,
        source: nil,
        components: [
            comp("beginning", "Beginning", ["The starting point of the journey"]),
            comp("milestones", "Milestones", ["Significant events, in order"]),
            comp("turningPoint", "Turning Point", ["The moment of meaningful change"]),
            comp("presentFuture", "Present / Future",
                 ["The current outcome and key lesson"]),
        ]
    )

    // MARK: - Shared source strings

    private static let lucas = "Lucas, The Art of Public Speaking (13th ed.)"
    private static let oklahomaState =
        "Oklahoma State University — https://open.library.okstate.edu/speech2713/"

    // MARK: - Construction

    /// Builds a component with a placeholder `order`; `make` assigns the real one from
    /// array position so the literals above cannot drift out of sequence.
    private static func comp(
        _ id: String,
        _ name: String,
        _ contains: [String],
        _ guideline: String? = nil
    ) -> SpeechPatternComponent {
        SpeechPatternComponent(
            id: id,
            name: name,
            contains: contains,
            aiGuideline: guideline,
            order: 0
        )
    }

    /// Assembles a catalog entry, re-indexing components so `order` always matches
    /// declaration position.
    private static func make(
        id: String,
        name: String,
        summary: String,
        purpose: SpeechPurpose,
        source: String?,
        components: [SpeechPatternComponent]
    ) -> SpeechPattern {
        let ordered = components.enumerated().map { index, component in
            SpeechPatternComponent(
                id: component.id,
                name: component.name,
                contains: component.contains,
                aiGuideline: component.aiGuideline,
                order: index
            )
        }
        return SpeechPattern(
            id: id,
            name: name,
            summary: summary,
            purpose: purpose,
            components: ordered,
            sourceNote: source
        )
    }
}
