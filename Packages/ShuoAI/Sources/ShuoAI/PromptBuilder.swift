//
//  PromptBuilder.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Centralizes prompt/instruction text for every `SpeechAnalyzing` call, keeping prompt
// wording reviewable and testable as data rather than buried in
// `FoundationModelSpeechAnalyzer`'s control flow (CLAUDE.md §8).

import Foundation
import ShuoCore

/// Every instruction and prompt string the analyzer sends to the model.
///
/// Prompts live here rather than inline at the call sites so their wording can be read,
/// diffed, and tested as data. Prompt text is the highest-leverage and most volatile part
/// of an on-device LLM feature; buried inside control flow it becomes invisible in review.
///
/// Component guidance is rendered from `SpeechPatternCatalog` rather than restated here,
/// so `Docs/SPEECH_PATTERNS.md` stays the single source of truth for what belongs in each
/// slot.
enum PromptBuilder {

    // MARK: - Classification

    static let classificationInstructions = """
        You analyze speech transcripts for a public-speaking practice app.

        You do two things in one pass:
        1. Judge whether the transcript is actually a speech, talk, or presentation draft.
        2. If it is, rank the structure patterns that best match how it is already organized.

        Rules:
        - Judge the transcript as a DRAFT. Rough, rambling, unfinished, or informal speech \
        is still a speech — never reject it for being unpolished.
        - Reject only when the text is genuinely not a speech: a shopping list, source \
        code, an invoice, a chat log, meeting minutes, random characters, or a \
        transcription of silence or music.
        - Rank patterns by how the transcript is ALREADY organized, not by how it could \
        be improved.
        - Use only the pattern identifiers you are given, copied exactly.
        """

    /// The classification prompt. `candidates` is always the catalog subset for the user's
    /// chosen purpose, so the model is never asked to consider a pattern from another one.
    static func classificationPrompt(
        transcript: String,
        purpose: SpeechPurpose,
        candidates: [SpeechPattern]
    ) -> String {
        """
        The speaker's goal is \(purpose.title.lowercased()).

        Available structure patterns:
        \(candidates.map { "- \($0.id) — \($0.name): \($0.summary)" }.joined(separator: "\n"))

        Transcript:
        \"\"\"
        \(transcript)
        \"\"\"

        Decide whether this is a usable speech draft. If it is, return the \
        \(ClassifyTranscriptUseCase.suggestionCount) best-matching pattern identifiers, \
        best first. If it is not, give the rejection reason and return no patterns.
        """
    }

    // MARK: - Key points

    static let keyPointsInstructions = """
        You map speech transcripts onto a fixed structure for a public-speaking practice app.

        You are given a structure with named components. For each component, extract the \
        part of the transcript that belongs to it.

        Rules:
        - Extract and lightly condense what the speaker ACTUALLY said. Never invent \
        content, examples, statistics, or conclusions.
        - If the transcript contains nothing for a component, omit that component \
        entirely. Do not guess, and do not write filler.
        - Omitting a component is the correct, expected answer whenever the draft does not \
        cover it. An incomplete draft is normal.
        - Never describe what is missing. "There is no call to action in the transcript" \
        is not an extraction — leave that component out instead.
        - Use only the component names you are given, copied exactly.
        - Keep each extraction to one or two sentences.
        """

    static func keyPointsPrompt(transcript: String, pattern: SpeechPattern) -> String {
        """
        Structure: \(pattern.name) — \(pattern.summary)

        Components:
        \(pattern.components.map(componentGuidance).joined(separator: "\n"))

        Transcript:
        \"\"\"
        \(transcript)
        \"\"\"

        For each component the transcript actually covers, extract the relevant content. \
        Omit components the transcript does not cover.
        """
    }

    /// One component as a prompt bullet: its name, what belongs in it, and its extraction
    /// guideline where the catalog defines one.
    private static func componentGuidance(_ component: SpeechPatternComponent) -> String {
        var line = "- \(component.name): \(component.contains.joined(separator: "; "))"
        if let guideline = component.aiGuideline {
            line += " (\(guideline))"
        }
        return line
    }

    // MARK: - Refinement

    static let refinementInstructions = """
        You restructure speech drafts for a public-speaking practice app.

        Rewrite the speaker's transcript so it follows a given structure, in the order that \
        structure defines.

        Rules:
        - The transcript is your material. Reorder it, and keep essentially all of it.
        - Preserve the speaker's own content, voice, and examples. You are reorganizing \
        their words, not writing a new speech and not summarizing one.
        - Keep the rewrite close to the length of the original. Removing filler should \
        shorten it slightly, never substantially.
        - Never invent facts, statistics, anecdotes, or conclusions the speaker did not give.
        - Where the draft does not cover part of the structure, leave it out. Do not write \
        material to fill the gap.
        - Remove filler words and false starts. Keep it natural to say out loud.
        - Return only the rewritten speech, with no headings, labels, or commentary.
        """

    /// Words below which a length target is noise rather than guidance — a two-line draft
    /// has no meaningful budget to hit.
    static let minimumWordsForLengthTarget = 40

    /// The floor is 80% of the original rather than an exact match: removing filler and
    /// false starts genuinely should shorten a spoken draft a little.
    static func minimumRewriteWords(forOriginalWords count: Int) -> Int {
        count * 4 / 5
    }

    /// The refinement prompt.
    ///
    /// Absent key points are named as gaps rather than dropped silently. Making the gaps
    /// explicit turns "don't invent content" into a concrete, checkable instruction, which
    /// holds up better on a small model than the general rule alone.
    ///
    /// The outline is labelled as running order, and the length target is stated in words,
    /// because without both the model reads the outline as its source material and returns
    /// something outline-length — a few sentences standing in for a whole speech.
    static func refinementPrompt(
        transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) -> String {
        let covered = keyPoints.filter { !$0.isAbsent }
        let gaps = keyPoints.filter { $0.isAbsent }

        var prompt = """
            Structure: \(pattern.name) — \(pattern.summary)

            Running order — these name the sections and their sequence. They are not the \
            material to write from; the transcript below is.
            \(covered.map { "- \($0.componentName): \($0.text)" }.joined(separator: "\n"))
            """

        if !gaps.isEmpty {
            prompt += """


                The draft does not cover these components. Leave them out entirely; do not \
                write content for them:
                \(gaps.map { "- \($0.componentName)" }.joined(separator: "\n"))
                """
        }

        prompt += """


            Original transcript:
            \"\"\"
            \(transcript)
            \"\"\"

            Rewrite the transcript above so its content runs in the order given, keeping \
            everything the speaker said.
            """

        let wordCount = transcript.split(whereSeparator: \.isWhitespace).count
        if wordCount >= minimumWordsForLengthTarget {
            prompt += """


                The transcript is about \(wordCount) words. Your rewrite should be a \
                similar length — at least \(minimumRewriteWords(forOriginalWords: wordCount)) \
                words. Do not summarize.
                """
        }

        return prompt
    }
}
