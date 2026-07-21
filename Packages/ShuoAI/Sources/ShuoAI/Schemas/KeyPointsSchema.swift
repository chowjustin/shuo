//
//  KeyPointsSchema.swift
//  ShuoAI
//

// The generation schema for the key-point extraction pass, built dynamically because the
// valid component names depend on which pattern is being applied. Property names are
// declared here and read by `GeneratedContentMapper`.

import Foundation
import FoundationModels
import ShuoCore

/// Builds the `GenerationSchema` that constrains a key-point extraction response.
///
/// Dynamic for the same reason as `ClassificationSchema`: the legal component names are
/// whichever pattern is being applied, which isn't known until runtime. Constraining
/// `component` to that exact list means the model can only label content with a slot that
/// really exists, which is what makes `KeyPointNormalizer`'s name-matching path reliable
/// instead of best-effort.
///
/// There is deliberately **no minimum element count**. A draft that covers only two of
/// five components should return two key points; forcing five would push the model into
/// inventing content for the gaps, which is the exact failure the "-" rule exists to
/// prevent.
enum KeyPointsSchema {

    /// Property names, shared with `GeneratedContentMapper`.
    enum Key {
        static let keyPoints = "keyPoints"
        static let component = "component"
        static let content = "content"
    }

    /// - Parameter pattern: The pattern being applied. Its component names become the only
    ///   labels the model can emit.
    /// - Throws: `ShuoError.aiGenerationFailed` if the schema cannot be assembled.
    static func make(pattern: SpeechPattern) throws -> GenerationSchema {
        let keyPoint = DynamicGenerationSchema(
            name: "ExtractedKeyPoint",
            description: "One component of the structure, and what the transcript said about it.",
            properties: [
                DynamicGenerationSchema.Property(
                    name: Key.component,
                    description: "The component name this content belongs to.",
                    schema: DynamicGenerationSchema(
                        name: "ComponentName",
                        anyOf: pattern.components.map(\.name)
                    )
                ),
                DynamicGenerationSchema.Property(
                    name: Key.content,
                    description: "What the speaker actually said for this component, condensed to one or two sentences.",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
            ]
        )

        let root = DynamicGenerationSchema(
            name: "ExtractedKeyPoints",
            description: "The components of the structure that the transcript covers.",
            properties: [
                DynamicGenerationSchema.Property(
                    name: Key.keyPoints,
                    description: "One entry per component the transcript covers. Omit components it does not cover.",
                    schema: DynamicGenerationSchema(
                        arrayOf: keyPoint,
                        maximumElements: pattern.components.count
                    )
                ),
            ]
        )

        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            throw ShuoError.aiGenerationFailed
        }
    }
}
