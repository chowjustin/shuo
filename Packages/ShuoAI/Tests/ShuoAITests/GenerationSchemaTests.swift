//
//  GenerationSchemaTests.swift
//  ShuoAITests
//

// Asserts the dynamic schemas actually assemble for every catalog entry.
//
// `GenerationSchema(root:dependencies:)` throws, and a malformed dynamic schema fails at
// *runtime* rather than compile time — which for this app would mean analysis failing on
// one specific pattern nobody happened to try. Building all 23 here catches that in a
// test that needs no model and no device.

import Foundation
import Testing
import FoundationModels
import ShuoCore
@testable import ShuoAI

@Suite("Generation schema construction")
struct GenerationSchemaTests {

    @Test("A classification schema builds for every purpose's candidate set")
    func classificationSchemaBuildsForEveryPurpose() throws {
        for purpose in SpeechPurpose.allCases {
            let candidates = SpeechPatternCatalog.patterns(for: purpose)
            #expect(throws: Never.self) {
                try ClassificationSchema.make(candidates: candidates)
            }
        }
    }

    @Test("A classification schema builds for a single candidate")
    func classificationSchemaBuildsForOneCandidate() throws {
        let candidate = try #require(SpeechPatternCatalog.pattern(id: "persuade.prep"))

        #expect(throws: Never.self) {
            try ClassificationSchema.make(candidates: [candidate])
        }
    }

    @Test("A key points schema builds for every pattern in the catalog")
    func keyPointsSchemaBuildsForEveryPattern() throws {
        // The one that would otherwise fail late and pattern-specifically.
        for pattern in SpeechPatternCatalog.all {
            #expect(throws: Never.self) {
                try KeyPointsSchema.make(pattern: pattern)
            }
        }
    }
}
