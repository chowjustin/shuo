//
//  KeyPointNormalizerTests.swift
//  ShuoCoreTests
//

// The normalizer is the guarantee behind "one key point per component, '-' where the
// transcript said nothing". Everything downstream renders positionally on that basis, so
// each way a small on-device model can misbehave gets its own test.

import Testing
@testable import ShuoCore

@Suite("Key point normalizer")
struct KeyPointNormalizerTests {

    private let normalizer = KeyPointNormalizer()

    /// Five components: topicOverview, category1, category2, category3, closingSummary.
    private var topical: SpeechPattern {
        guard let pattern = SpeechPatternCatalog.pattern(id: "inform.topical") else {
            preconditionFailure("inform.topical must exist in the catalog")
        }
        return pattern
    }

    private func keyPoint(_ componentID: String, _ name: String, _ text: String) -> KeyPoint {
        KeyPoint(componentID: componentID, componentName: name, text: text, orderIndex: 0)
    }

    @Test("Produces exactly one key point per component, in component order")
    func oneKeyPointPerComponent() {
        let result = normalizer.normalize([], for: topical)

        #expect(result.count == topical.components.count)
        #expect(result.map(\.componentID) == topical.components.map(\.id))
        #expect(result.map(\.orderIndex) == Array(0..<topical.components.count))
    }

    @Test("An empty input yields an all-absent set rather than an error")
    func emptyInputIsAllAbsent() {
        let result = normalizer.normalize([], for: topical)

        #expect(result.allSatisfy { $0.isAbsent })
        #expect(result.allSatisfy { $0.text == KeyPoint.absentText })
    }

    @Test("Matches components by exact id")
    func matchesByID() throws {
        let result = normalizer.normalize(
            [keyPoint("category2", "Category 2", "Worker autonomy.")],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "category2" })
        #expect(matched.text == "Worker autonomy.")
        #expect(!matched.isAbsent)
    }

    @Test("Falls back to matching by display name when the id is unrecognized")
    func matchesByName() throws {
        // The realistic failure: the model echoes the human-readable label it was shown
        // rather than the slug it was asked for.
        let result = normalizer.normalize(
            [keyPoint("", "Closing Summary", "Remote work is here to stay.")],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "closingSummary" })
        #expect(matched.text == "Remote work is here to stay.")
    }

    @Test("Name matching tolerates case and punctuation differences")
    func nameMatchingIsLenient() throws {
        let result = normalizer.normalize(
            [keyPoint("", "topic overview:", "Remote work since 2020.")],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "topicOverview" })
        #expect(matched.text == "Remote work since 2020.")
    }

    @Test("An id match wins over a name match for the same component")
    func idMatchTakesPrecedenceOverName() throws {
        let result = normalizer.normalize(
            [
                keyPoint("", "Category 1", "From the name match."),
                keyPoint("category1", "Something else entirely", "From the id match."),
            ],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "category1" })
        #expect(matched.text == "From the id match.")
    }

    @Test("On duplicate components the first occurrence wins")
    func duplicatesKeepFirst() throws {
        let result = normalizer.normalize(
            [
                keyPoint("category1", "Category 1", "First."),
                keyPoint("category1", "Category 1", "Second."),
            ],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "category1" })
        #expect(matched.text == "First.")
        #expect(result.count == topical.components.count)
    }

    @Test("Components the model invented are dropped")
    func dropsUnknownComponents() {
        let result = normalizer.normalize(
            [
                keyPoint("category1", "Category 1", "Real content."),
                keyPoint("category7", "Category 7", "Invented content."),
                keyPoint("epilogue", "Epilogue", "Also invented."),
            ],
            for: topical
        )

        #expect(result.count == topical.components.count)
        #expect(!result.contains { $0.componentID == "category7" })
        #expect(!result.contains { $0.text.contains("Invented") })
    }

    @Test("Blank, whitespace-only, and literal '-' text all count as absent")
    func blankTextIsAbsent() {
        let result = normalizer.normalize(
            [
                keyPoint("topicOverview", "Topic Overview", ""),
                keyPoint("category1", "Category 1", "   \n  "),
                keyPoint("category2", "Category 2", "-"),
            ],
            for: topical
        )

        #expect(result.filter { ["topicOverview", "category1", "category2"].contains($0.componentID) }
            .allSatisfy { $0.isAbsent })
    }

    @Test("Surrounding whitespace is trimmed from filled key points")
    func trimsWhitespace() throws {
        let result = normalizer.normalize(
            [keyPoint("category1", "Category 1", "  Cost savings.\n\n")],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "category1" })
        #expect(matched.text == "Cost savings.")
    }

    @Test("Out-of-order input is reordered to component order")
    func reordersInput() {
        let result = normalizer.normalize(
            [
                keyPoint("closingSummary", "Closing Summary", "Last."),
                keyPoint("topicOverview", "Topic Overview", "First."),
            ],
            for: topical
        )

        #expect(result.first?.componentID == "topicOverview")
        #expect(result.last?.componentID == "closingSummary")
        #expect(result.first?.text == "First.")
    }

    @Test("Absent key points carry ghost text derived from the component's hints")
    func absentKeyPointsCarrySuggestions() throws {
        let result = normalizer.normalize([], for: topical)
        let overview = try #require(result.first { $0.componentID == "topicOverview" })

        // Docs/SPEECH_PATTERNS.md §2.1: Main subject / Brief introduction / Scope.
        #expect(overview.suggestion?.contains("Main subject") == true)
    }

    @Test("Filled key points carry no ghost text")
    func filledKeyPointsHaveNoSuggestion() throws {
        let result = normalizer.normalize(
            [keyPoint("topicOverview", "Topic Overview", "Remote work.")],
            for: topical
        )
        let overview = try #require(result.first { $0.componentID == "topicOverview" })

        #expect(overview.suggestion == nil)
    }

    @Test("A blank component name cannot shadow a real match")
    func blankNamesAreIgnoredForMatching() throws {
        let result = normalizer.normalize(
            [
                keyPoint("", "", "Orphaned content."),
                keyPoint("category3", "Category 3", "Real content."),
            ],
            for: topical
        )

        let matched = try #require(result.first { $0.componentID == "category3" })
        #expect(matched.text == "Real content.")
        #expect(!result.contains { $0.text == "Orphaned content." })
    }

    @Test("Normalizes correctly for a three-component pattern too")
    func worksForShortPatterns() throws {
        let cer = try #require(SpeechPatternCatalog.pattern(id: "persuade.cer"))
        let result = normalizer.normalize(
            [keyPoint("claim", "Claim", "We should adopt a four-day week.")],
            for: cer
        )

        #expect(result.count == 3)
        #expect(result.map(\.componentID) == ["claim", "evidence", "reasoning"])
        #expect(result[0].text == "We should adopt a four-day week.")
        #expect(result[1].isAbsent)
        #expect(result[2].isAbsent)
    }
}
