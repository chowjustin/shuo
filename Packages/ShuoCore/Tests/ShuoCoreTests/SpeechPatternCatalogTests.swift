//
//  SpeechPatternCatalogTests.swift
//  ShuoCoreTests
//

// Structural invariants of the pattern catalog. These are cheap guards against
// transcription slips in a hand-authored 23-entry table — a duplicated id or a component
// list that silently lost an entry would otherwise surface as a confusing runtime bug in
// classification or normalization.

import Foundation
import Testing
@testable import ShuoCore

@Suite("Speech pattern catalog")
struct SpeechPatternCatalogTests {

    @Test("Catalog holds every pattern documented in Docs/SPEECH_PATTERNS.md")
    func catalogCount() {
        #expect(SpeechPatternCatalog.all.count == 23)
        #expect(SpeechPatternCatalog.patterns(for: .inform).count == 8)
        #expect(SpeechPatternCatalog.patterns(for: .persuade).count == 7)
        #expect(SpeechPatternCatalog.patterns(for: .inspire).count == 8)
    }

    @Test("Every pattern id is unique across the whole catalog")
    func patternIDsAreUnique() {
        let ids = SpeechPatternCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every pattern id is namespaced by its own purpose")
    func patternIDsAreNamespacedByPurpose() {
        for pattern in SpeechPatternCatalog.all {
            #expect(
                pattern.id.hasPrefix("\(pattern.purpose.rawValue)."),
                "\(pattern.id) is not namespaced under \(pattern.purpose.rawValue)"
            )
        }
    }

    @Test("patterns(for:) returns only patterns belonging to that purpose")
    func patternsForPurposeAreScoped() {
        for purpose in SpeechPurpose.allCases {
            let patterns = SpeechPatternCatalog.patterns(for: purpose)
            #expect(!patterns.isEmpty)
            #expect(patterns.allSatisfy { $0.purpose == purpose })
        }
    }

    @Test("Every pattern has at least three components")
    func patternsHaveComponents() {
        for pattern in SpeechPatternCatalog.all {
            #expect(
                pattern.components.count >= 3,
                "\(pattern.id) has only \(pattern.components.count) components"
            )
        }
    }

    @Test("Component order is contiguous and zero-based within every pattern")
    func componentOrdersAreContiguous() {
        for pattern in SpeechPatternCatalog.all {
            let orders = pattern.components.map(\.order)
            #expect(
                orders == Array(0..<pattern.components.count),
                "\(pattern.id) has non-contiguous component orders: \(orders)"
            )
        }
    }

    @Test("Component ids are unique within their pattern")
    func componentIDsAreUniqueWithinPattern() {
        for pattern in SpeechPatternCatalog.all {
            let ids = pattern.components.map(\.id)
            #expect(Set(ids).count == ids.count, "\(pattern.id) has duplicate component ids")
        }
    }

    @Test("Component display names are unique within their pattern")
    func componentNamesAreUniqueWithinPattern() {
        // Name-based matching is how the model's labels are resolved back to components,
        // so two components sharing a name would make that lookup ambiguous.
        for pattern in SpeechPatternCatalog.all {
            let names = pattern.components.map { SpeechPattern.normalizeForMatching($0.name) }
            #expect(Set(names).count == names.count, "\(pattern.id) has duplicate component names")
        }
    }

    @Test("Every component carries at least one 'contains' hint for the prompt")
    func componentsHaveGuidance() {
        for pattern in SpeechPatternCatalog.all {
            for component in pattern.components {
                #expect(
                    !component.contains.isEmpty,
                    "\(pattern.id)/\(component.id) has no guidance to render into the prompt"
                )
            }
        }
    }

    @Test("pattern(id:) finds a known pattern and rejects an unknown one")
    func lookupByID() {
        #expect(SpeechPatternCatalog.pattern(id: "persuade.prep")?.name == "PREP")
        #expect(SpeechPatternCatalog.pattern(id: "persuade.nonsense") == nil)
    }

    @Test("patterns(ids:) preserves ranking order and drops unknown ids")
    func lookupByIDsPreservesOrder() {
        let resolved = SpeechPatternCatalog.patterns(
            ids: ["inform.spatial", "not.a.pattern", "inform.topical"]
        )
        #expect(resolved.map(\.id) == ["inform.spatial", "inform.topical"])
    }

    @Test("Cause-Effect and Chronological exist separately under two purposes")
    func deliberateCrossPurposeDuplicates() {
        // Documented in Docs/SPEECH_PATTERNS.md §6 as intentional: same structure, different
        // guidance, separate ids so each purpose's prompt stays unconditional.
        #expect(SpeechPatternCatalog.pattern(id: "inform.causeEffect") != nil)
        #expect(SpeechPatternCatalog.pattern(id: "persuade.causeEffect") != nil)
        #expect(SpeechPatternCatalog.pattern(id: "inform.chronological") != nil)
        #expect(SpeechPatternCatalog.pattern(id: "inspire.chronological") != nil)
    }

    @Test("Component lookup by display name ignores case and punctuation")
    func componentLookupByName() throws {
        let topical = try #require(SpeechPatternCatalog.pattern(id: "inform.topical"))
        #expect(topical.component(matchingName: "Category 1")?.id == "category1")
        #expect(topical.component(matchingName: "category  1.")?.id == "category1")
        #expect(topical.component(matchingName: "Category 9") == nil)
        #expect(topical.component(matchingName: "  ") == nil)
    }

    // MARK: - Verbatim spec pins

    /// One row of a component table in `Docs/SPEECH_PATTERNS.md`.
    ///
    /// `contains` is the document's **Contains** cell verbatim, semicolons and all. The
    /// catalog stores that cell split into an array with each item's first letter
    /// capitalized; `containsHints(fromSpecCell:)` below applies exactly that
    /// transformation so what is written here stays a literal transcription of the doc
    /// rather than a pre-digested copy of the code.
    struct SpecComponent: Sendable {
        let name: String
        let contains: String
        /// The **AI Guideline** cell, or nil where the document's table has no such column
        /// or leaves it as `—`.
        let guideline: String?

        init(_ name: String, _ contains: String, _ guideline: String? = nil) {
            self.name = name
            self.contains = contains
            self.guideline = guideline
        }
    }

    /// One entry of `Docs/SPEECH_PATTERNS.md`, transcribed by hand from the document rather
    /// than from `SpeechPatternCatalog`. Deriving these from the catalog would make the
    /// test tautological — the whole point is that it fails when the code drifts from the
    /// doc, and the doc wins.
    struct SpecEntry: Sendable {
        let id: String
        let name: String
        /// The one-line description under the entry's heading.
        ///
        /// **nil means the document states none** — not that the catalog's summary is
        /// unimportant. 14 of the 23 entries (every §3 pattern but PREP, and all of §4)
        /// jump straight from heading to component table, so the summaries the catalog
        /// ships for those are author-written text with no upstream source to pin against.
        /// They are deliberately left unpinned rather than back-filled from the code,
        /// which would freeze in whatever the code happens to say today. Closing this gap
        /// properly means adding the missing sentences to the spec first.
        let summary: String?
        let components: [SpecComponent]

        var componentNames: [String] { components.map(\.name) }
    }

    /// Splits a document **Contains** cell into the array shape the catalog stores:
    /// semicolon-separated, trimmed, first letter capitalized. Verified to hold for all
    /// 23 entries — every catalog hint is this function applied to the doc's cell.
    static func containsHints(fromSpecCell cell: String) -> [String] {
        cell.split(separator: ";").map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first else { return trimmed }
            return first.uppercased() + String(trimmed.dropFirst())
        }
    }

    /// Every entry, in document order. Split by purpose because a single 23-element
    /// literal of nested arrays defeats the type checker — the same reason
    /// `SpeechPatternCatalog` itself is written one `static let` per pattern.
    static let spec: [SpecEntry] = informSpec + persuadeSpec + inspireSpec

    /// §2 — To Inform.
    static let informSpec: [SpecEntry] = [
        SpecEntry(
            id: "inform.topical",
            name: "Topical (Categorical)",
            summary: "Organizes information into categories or major aspects of the topic.",
            components: [
                SpecComponent("Topic Overview",
                              "Main subject; brief introduction; scope of discussion",
                              "Extract the overall topic and explain what will be discussed."),
                SpecComponent("Category 1",
                              "First major aspect; supporting explanation; facts/examples",
                              "Identify the first independent category that explains the topic."),
                SpecComponent("Category 2",
                              "Second major aspect; supporting explanation; facts/examples"),
                SpecComponent("Category 3", "Third major aspect; supporting explanation"),
                SpecComponent("Closing Summary", "Recap of categories; final takeaway"),
            ]
        ),
        SpecEntry(
            id: "inform.chronological",
            name: "Chronological",
            summary: "Presents information according to time order.",
            components: [
                SpecComponent("Beginning", "Starting event; initial situation",
                              "Find the earliest event."),
                SpecComponent("Middle", "Sequence of developments; progression"),
                SpecComponent("End", "Final event; result"),
                SpecComponent("Takeaway", "Overall timeline summary"),
            ]
        ),
        SpecEntry(
            id: "inform.causeEffect",
            name: "Cause-Effect",
            summary: "Explains why something happened and what followed from it.",
            components: [
                SpecComponent("Cause", "Root causes; contributing factors",
                              "Identify WHY something happened."),
                SpecComponent("Effects", "Immediate impacts; long-term impacts",
                              "Identify WHAT happened because of the causes."),
                SpecComponent("Conclusion", "Overall implication"),
            ]
        ),
        SpecEntry(
            id: "inform.sequential",
            name: "Sequential (Process)",
            summary: "Walks through a process step by step toward an outcome.",
            components: [
                SpecComponent("Goal", "Desired outcome"),
                SpecComponent("Step 1", "First action"),
                SpecComponent("Step 2", "Second action"),
                SpecComponent("Step 3", "Remaining actions"),
                SpecComponent("Expected Result", "Final outcome"),
            ]
        ),
        SpecEntry(
            id: "inform.spatial",
            name: "Spatial",
            summary: "Organizes information by physical location or arrangement.",
            components: [
                SpecComponent("Overall Subject", "Object/place overview"),
                SpecComponent("Area 1", "Description; importance"),
                SpecComponent("Area 2", "Description; importance"),
                SpecComponent("Area 3", "Description; importance"),
                SpecComponent("Overall Understanding", "Relationship between locations"),
            ]
        ),
        SpecEntry(
            id: "inform.definition",
            name: "Definition",
            // The document italicizes "is"; markdown emphasis is not part of the string.
            summary: "Explains what something is and why it matters.",
            components: [
                SpecComponent("Definition", "Formal definition"),
                SpecComponent("Characteristics", "Key attributes"),
                SpecComponent("Examples", "Illustrations"),
                SpecComponent("Importance", "Why the audience should understand it"),
            ]
        ),
        SpecEntry(
            id: "inform.classification",
            name: "Classification",
            summary: "Sorts a subject into categories by criteria.",
            components: [
                SpecComponent("Main Topic", "Object being classified"),
                SpecComponent("Category A", "Criteria; explanation"),
                SpecComponent("Category B", "Criteria; explanation"),
                SpecComponent("Comparison Summary", "Differences among categories"),
            ]
        ),
        SpecEntry(
            id: "inform.comparisonContrast",
            name: "Comparison / Contrast",
            summary: "Sets two subjects side by side.",
            components: [
                SpecComponent("Subject A", "Key features"),
                SpecComponent("Subject B", "Key features"),
                SpecComponent("Similarities", "Shared characteristics"),
                SpecComponent("Differences", "Contrasting characteristics"),
                SpecComponent("Conclusion", "Main insight"),
            ]
        ),
    ]

    /// §3 — To Persuade. Only PREP carries a summary sentence in the document.
    static let persuadeSpec: [SpecEntry] = [
        SpecEntry(
            id: "persuade.prep",
            name: "PREP",
            summary: "Claim, justification, evidence, restated claim.",
            components: [
                SpecComponent(
                    "Point",
                    "One clear claim or recommendation; the speaker's stance; the central persuasive message",
                    "Extract the main opinion or recommendation as one concise sentence."),
                SpecComponent(
                    "Reason",
                    "Logical justification; benefits/rationale; why the audience should believe the claim",
                    "Identify the strongest supporting reason directly connected to the point."),
                SpecComponent(
                    "Example",
                    "Personal experience; real-world example; statistics; research findings; case study",
                    "Extract the most convincing evidence that supports the reason."),
                SpecComponent(
                    "Reinforced Point",
                    "Restated claim; strong call-to-action or memorable closing",
                    "Rewrite the original point as a stronger concluding statement that reinforces the desired action."),
            ]
        ),
        SpecEntry(
            id: "persuade.monroe",
            name: "Monroe's Motivated Sequence",
            summary: nil, // §3.2 states no summary sentence.
            components: [
                SpecComponent("Attention",
                              "Hook; problem introduction; surprising fact; question"),
                SpecComponent("Need", "Problem explanation; why the audience should care"),
                SpecComponent("Satisfaction", "Proposed solution"),
                SpecComponent("Visualization",
                              "The future if the solution is adopted (or ignored)"),
                SpecComponent("Action", "Clear call to action"),
            ]
        ),
        SpecEntry(
            id: "persuade.problemCauseSolution",
            name: "Problem-Cause-Solution",
            summary: nil, // §3.3 states no summary sentence.
            components: [
                SpecComponent("Problem", "Current issue"),
                SpecComponent("Cause", "Root causes"),
                SpecComponent("Solution", "Proposed solution"),
                SpecComponent("Benefits", "Expected outcomes"),
            ]
        ),
        SpecEntry(
            id: "persuade.comparativeAdvantages",
            name: "Comparative Advantages",
            summary: nil, // §3.4 states no summary sentence.
            components: [
                SpecComponent("Option", "Recommended choice"),
                SpecComponent("Alternative", "Other choices"),
                SpecComponent("Comparison", "Strengths and weaknesses"),
                SpecComponent("Recommendation", "Why the recommended option is best"),
            ]
        ),
        SpecEntry(
            id: "persuade.causeEffect",
            name: "Cause-Effect (persuasive)",
            // §3.5's prose is a cross-reference to §2.3, not a display summary, so there
            // is no sentence here to pin.
            summary: nil,
            components: [
                SpecComponent("Cause", "Root causes; contributing factors",
                              "Identify WHY something happened."),
                SpecComponent("Effects", "Immediate impacts; long-term impacts",
                              "Identify WHAT happened because of the causes."),
                SpecComponent("Conclusion", "Persuasive implication; recommended action",
                              "State what the audience should conclude or do."),
            ]
        ),
        SpecEntry(
            id: "persuade.refutation",
            name: "Refutation",
            summary: nil, // §3.6 states no summary sentence.
            components: [
                SpecComponent("Claim", "Opposing viewpoint"),
                SpecComponent("Counterargument", "Weaknesses; missing evidence"),
                SpecComponent("Evidence", "Supporting evidence for the rebuttal"),
                SpecComponent("Conclusion", "Stronger position"),
            ]
        ),
        SpecEntry(
            id: "persuade.cer",
            name: "Claim-Evidence-Reasoning (CER)",
            summary: nil, // §3.7 states no summary sentence.
            components: [
                SpecComponent("Claim", "Main argument"),
                SpecComponent("Evidence", "Facts; statistics; examples"),
                SpecComponent("Reasoning",
                              "Explanation of how the evidence supports the claim"),
            ]
        ),
    ]

    /// §4 — To Inspire. No entry in this section carries a summary sentence.
    static let inspireSpec: [SpecEntry] = [
        SpecEntry(
            id: "inspire.challengeChoiceOutcome",
            name: "Challenge–Choice–Outcome",
            summary: nil, // §4.1 states no summary sentence.
            components: [
                SpecComponent(
                    "Challenge",
                    "The obstacle, setback, or defining moment that created tension or required action"),
                SpecComponent(
                    "Choice",
                    "The decision, mindset, or action taken to address the challenge"),
                SpecComponent(
                    "Outcome",
                    "The result, lesson learned, or positive transformation that inspires the audience"),
            ]
        ),
        SpecEntry(
            id: "inspire.narrativeArc",
            name: "Narrative / Storytelling Arc",
            summary: nil, // §4.2 states no summary sentence.
            components: [
                SpecComponent("Beginning", "Setting, context, and characters"),
                SpecComponent("Conflict", "The central challenge or tension"),
                SpecComponent("Climax", "The turning point or decisive moment"),
                SpecComponent("Resolution", "How the situation was resolved"),
                SpecComponent("Takeaway", "The lesson or message for the audience"),
            ]
        ),
        SpecEntry(
            id: "inspire.publicNarrative",
            name: "Public Narrative (Marshall Ganz)",
            summary: nil, // §4.3 states no summary sentence.
            components: [
                SpecComponent("Story of Self",
                              "Why this issue matters personally to the speaker"),
                SpecComponent("Story of Us",
                              "Connection from the personal story to shared values or experiences"),
                SpecComponent("Story of Now",
                              "The urgency; inspiring immediate collective action"),
            ]
        ),
        SpecEntry(
            id: "inspire.herosJourney",
            name: "Hero's Journey",
            summary: nil, // §4.4 states no summary sentence.
            components: [
                SpecComponent("Ordinary World", "Initial situation before change"),
                SpecComponent("Challenge / Call to Adventure",
                              "The event that initiates change"),
                SpecComponent("Trials", "Obstacles and growth throughout the journey"),
                SpecComponent("Transformation",
                              "The key insight or personal change achieved"),
                SpecComponent("Return / Message",
                              "The lesson shared; how it inspires the audience"),
            ]
        ),
        SpecEntry(
            id: "inspire.personalStory",
            name: "Personal Story",
            summary: nil, // §4.5 states no summary sentence.
            components: [
                SpecComponent("Situation", "The context"),
                SpecComponent("Experience", "What happened"),
                SpecComponent("Reflection", "What was learned"),
                SpecComponent("Application", "How the lesson connects to the audience"),
            ]
        ),
        SpecEntry(
            id: "inspire.problemSolution",
            name: "Problem–Solution",
            summary: nil, // §4.6 states no summary sentence.
            components: [
                SpecComponent("Problem",
                              "An issue that resonates emotionally with the audience"),
                SpecComponent("Solution", "The action or idea that addressed the problem"),
                SpecComponent("Impact", "The positive change created"),
                SpecComponent("Inspiration",
                              "Encouragement to take a similar perspective or action"),
            ]
        ),
        SpecEntry(
            id: "inspire.beforeAfterBridge",
            name: "Before–After–Bridge (BAB)",
            summary: nil, // §4.7 states no summary sentence.
            components: [
                SpecComponent("Before", "The current reality or pain point"),
                SpecComponent("After", "A vivid picture of the desired future state"),
                SpecComponent("Bridge",
                              "How to move from the current state to the desired future"),
            ]
        ),
        SpecEntry(
            id: "inspire.chronological",
            name: "Chronological (inspirational)",
            summary: nil, // §4.8 states no summary sentence.
            components: [
                SpecComponent("Beginning", "The starting point of the journey"),
                SpecComponent("Milestones", "Significant events, in order"),
                SpecComponent("Turning Point", "The moment of meaningful change"),
                SpecComponent("Present / Future", "The current outcome and key lesson"),
            ]
        ),
    ]

    @Test("Every pattern's name and ordered component names match the spec exactly",
          arguments: Self.spec)
    func patternMatchesSpec(entry: SpecEntry) throws {
        let pattern = try #require(
            SpeechPatternCatalog.pattern(id: entry.id),
            "Docs/SPEECH_PATTERNS.md documents \(entry.id) but the catalog has no such id"
        )
        #expect(
            pattern.name == entry.name,
            "\(entry.id) display name is \"\(pattern.name)\", spec says \"\(entry.name)\""
        )
        #expect(
            pattern.components.map(\.name) == entry.componentNames,
            "\(entry.id) components are \(pattern.components.map(\.name)), spec says \(entry.componentNames)"
        )
    }

    @Test("The catalog contains exactly the ids the spec documents, in document order")
    func catalogMatchesSpecIDsInOrder() {
        #expect(SpeechPatternCatalog.all.map(\.id) == Self.spec.map(\.id))
    }

    @Test("Every pattern display name is unique, so the twinned entries stay tellable apart")
    func patternNamesAreUnique() {
        // The spec qualifies "Cause-Effect (persuasive)" and "Chronological
        // (inspirational)" precisely so neither collides with its inform.* twin in the UI.
        let names = SpeechPatternCatalog.all.map(\.name)
        #expect(Set(names).count == names.count, "duplicate display names in \(names)")
    }

    @Test("Every component's 'contains' hints are the spec's wording, in the spec's order",
          arguments: Self.spec)
    func containsHintsMatchSpec(entry: SpecEntry) throws {
        let pattern = try #require(SpeechPatternCatalog.pattern(id: entry.id))
        try #require(pattern.components.count == entry.components.count)

        for (component, expected) in zip(pattern.components, entry.components) {
            let expectedHints = Self.containsHints(fromSpecCell: expected.contains)
            #expect(
                component.contains == expectedHints,
                "\(entry.id)/\(component.id) hints are \(component.contains), spec says \(expectedHints)"
            )
        }
    }

    @Test("Every AI Guideline is the spec's exact wording, and absent where the spec gives none",
          arguments: Self.spec)
    func aiGuidelinesMatchSpec(entry: SpecEntry) throws {
        // This is the pin that matters most: the guideline string is injected verbatim
        // into the generation prompt, so a reworded one is words the source material never
        // sanctioned — and unlike a wrong display name, nothing on screen reveals it.
        let pattern = try #require(SpeechPatternCatalog.pattern(id: entry.id))
        try #require(pattern.components.count == entry.components.count)

        for (component, expected) in zip(pattern.components, entry.components) {
            #expect(
                component.aiGuideline == expected.guideline,
                "\(entry.id)/\(component.id) guideline is \(component.aiGuideline.map { "\"\($0)\"" } ?? "nil"), spec says \(expected.guideline.map { "\"\($0)\"" } ?? "nil")"
            )
        }
    }

    @Test("Every summary the spec states is reproduced verbatim", arguments: Self.spec)
    func summaryMatchesSpec(entry: SpecEntry) throws {
        // Entries the document gives no summary sentence for are skipped rather than
        // pinned against the code — see `SpecEntry.summary`. `unsummarizedEntriesAreCounted`
        // keeps that skip list from growing unnoticed.
        guard let expected = entry.summary else { return }
        let pattern = try #require(SpeechPatternCatalog.pattern(id: entry.id))
        #expect(
            pattern.summary == expected,
            "\(entry.id) summary is \"\(pattern.summary)\", spec says \"\(expected)\""
        )
    }

    @Test("The spec leaves exactly fourteen entries without a summary to pin")
    func unsummarizedEntriesAreCounted() {
        // A tripwire on a known documentation gap. If this fails because the count fell,
        // someone added a sentence to Docs/SPEECH_PATTERNS.md — transcribe it into the
        // table above rather than relaxing the number.
        let unsummarized = Self.spec.filter { $0.summary == nil }.map(\.id)
        #expect(unsummarized.count == 14, "unsummarized entries: \(unsummarized)")

        // Whatever the doc says, the catalog must still show the user something.
        for pattern in SpeechPatternCatalog.all {
            #expect(
                !pattern.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(pattern.id) has a blank summary"
            )
        }
    }
}
