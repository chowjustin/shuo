//
//  UntitledScriptTitleTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 30/07/26.
//

import ShuoCore
import Testing

@Suite("Untitled script title")
struct UntitledScriptTitleTests {
    // MARK: - Formatting

    @Test("The first generated name is numbered, not bare")
    func firstNameIsNumbered() {
        #expect(UntitledScriptTitle.first == "Untitled Script 1")
    }

    @Test("A number is formatted as the stem followed by a single space")
    func namedFormatsWithOneSpace() {
        #expect(UntitledScriptTitle.named(7) == "Untitled Script 7")
        #expect(UntitledScriptTitle.named(42) == "Untitled Script 42")
    }

    @Test("Every name it writes is a name it recognises")
    func roundTripsItsOwnOutput() {
        for number in [1, 2, 9, 10, 99, 1000] {
            #expect(UntitledScriptTitle.number(in: UntitledScriptTitle.named(number)) == number)
        }
    }

    // MARK: - Recognition

    @Test("A generated name is recognised as generated")
    func recognisesGeneratedName() {
        #expect(UntitledScriptTitle.isGenerated("Untitled Script 3"))
    }

    @Test("The bare stem is not a generated name, since numbering starts at 1")
    func bareStemIsNotGenerated() {
        // The old scheme's placeholder. It is no longer something the app writes, so a
        // user who typed it exactly owns it like any other title.
        #expect(!UntitledScriptTitle.isGenerated("Untitled Script"))
        #expect(UntitledScriptTitle.number(in: "Untitled Script") == nil)
    }

    @Test("A title the user chose is never mistaken for a generated one")
    func userTitlesAreNotGenerated() {
        let userTitles = [
            "Why remote work stuck",
            "Untitled Script ideas",
            "Untitled Script 3 draft",
            "My Untitled Script 3",
            "Untitled Script -1",
            "Untitled Script 0",
            "Untitled Script  4",
            "Untitled Script4",
            "Untitled Script 4.5",
            "",
        ]
        for title in userTitles {
            #expect(!UntitledScriptTitle.isGenerated(title), "\(title) should not be generated")
        }
    }

    @Test("Recognition is case-sensitive, so a lowercased title stays the user's own")
    func recognitionIsCaseSensitive() {
        #expect(!UntitledScriptTitle.isGenerated("untitled script 4"))
        #expect(!UntitledScriptTitle.isGenerated("UNTITLED SCRIPT 4"))
    }

    @Test("Surrounding whitespace does not hide a generated name")
    func trimsBeforeMatching() {
        #expect(UntitledScriptTitle.number(in: "  Untitled Script 5  ") == 5)
    }

    @Test("Non-ASCII digits are not read as a number")
    func rejectsNonASCIIDigits() {
        #expect(UntitledScriptTitle.number(in: "Untitled Script ٣") == nil)
    }

    @Test("An absurdly long digit run is rejected rather than overflowing the next number")
    func rejectsUnboundedDigits() {
        let overlong = "Untitled Script " + String(repeating: "9", count: 30)
        #expect(UntitledScriptTitle.number(in: overlong) == nil)
        // The guarantee that matters: numbering past it does not trap.
        #expect(UntitledScriptTitle.next(after: [overlong]) == "Untitled Script 1")
    }

    // MARK: - Numbering

    @Test("With nothing stored, the next name is the first")
    func nextFromEmptyIsFirst() {
        #expect(UntitledScriptTitle.next(after: []) == "Untitled Script 1")
    }

    @Test("The next name is one past the highest number stored")
    func nextIsHighestPlusOne() {
        let stored = ["Untitled Script 1", "Untitled Script 2"]
        #expect(UntitledScriptTitle.next(after: stored) == "Untitled Script 3")
    }

    @Test("A gap left by a rename or deletion is not reused")
    func nextSkipsGaps() {
        // Highest-plus-one, deliberately: reusing 2 here would produce a second script
        // that had once been called the same thing as another.
        let stored = ["Untitled Script 1", "Untitled Script 5"]
        #expect(UntitledScriptTitle.next(after: stored) == "Untitled Script 6")
    }

    @Test("Order of the stored names does not matter")
    func nextIgnoresOrdering() {
        let stored = ["Untitled Script 3", "Untitled Script 10", "Untitled Script 2"]
        #expect(UntitledScriptTitle.next(after: stored) == "Untitled Script 11")
    }

    @Test("Numbering compares numerically, not as strings")
    func nextComparesNumerically() {
        // "9" sorts after "10" lexicographically; the answer must still be 11.
        #expect(UntitledScriptTitle.next(after: ["Untitled Script 9", "Untitled Script 10"])
            == "Untitled Script 11")
    }

    @Test("Titles the user chose are ignored when numbering")
    func nextIgnoresUserTitles() {
        let stored = ["Why remote work stuck", "Untitled Script ideas", "untitled script 99"]
        #expect(UntitledScriptTitle.next(after: stored) == "Untitled Script 1")
    }

    @Test("Duplicated generated names do not double-count")
    func nextHandlesDuplicates() {
        #expect(UntitledScriptTitle.next(after: ["Untitled Script 2", "Untitled Script 2"])
            == "Untitled Script 3")
    }
}
