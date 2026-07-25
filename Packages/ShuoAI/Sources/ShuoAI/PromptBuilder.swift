//
//  PromptBuilder.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore

/// Every instruction and prompt string the analyzer sends to the model.
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

    /// The classification prompt.
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

    /// One component as a prompt bullet: its name, what belongs in it, and its extraction guideline where the catalog defines one.
    private static func componentGuidance(_ component: SpeechPatternComponent) -> String {
        var line = "- \(component.name): \(component.contains.joined(separator: "; "))"
        if let guideline = component.aiGuideline {
            line += " (\(guideline))"
        }
        return line
    }

    // MARK: - Refinement

    static let refinementInstructions = """
        You write clean, engaging, deliverable speeches for a public-speaking practice app.

        You are given the ordered points a speech must make. DEVELOP them into a full, \
        polished speech the speaker could deliver as-is — not a list of the points.

        Rules:
        - Cover every point, in the given order, and develop each into one or more natural \
        spoken paragraphs. REPHRASE the points in your own words; never just repeat or \
        concatenate them.
        - Add a brief, natural opening and closing, and smooth transitions between points, so \
        it reads as one flowing speech.
        - You MAY add connective phrasing, transitions, and rhetorical framing to make it \
        engaging — but do NOT introduce new facts, statistics, examples, or claims that are \
        not in the points.
        - Write ONE continuous speech in flowing paragraphs, in a confident first-person \
        voice. Never use headings, section titles, numbered lists, bullet points, or labels, \
        and never repeat these instructions.
        - The result should be clearly more developed and polished than the bare points — a \
        real speech to deliver, natural to say out loud, no "um" or false starts.
        - Output only the finished speech.
        """

    /// The refinement prompt. Built from the key points, which ARE the speech's content — the
    /// raw transcript is deliberately NOT included in the covered case, because a small
    /// on-device model handed the transcript tends to echo it verbatim instead of writing
    /// from the points.
    static func refinementPrompt(
        transcript: String,
        pattern: SpeechPattern,
        keyPoints: [KeyPoint]
    ) -> String {
        let covered = keyPoints.filter { !$0.isAbsent }

        guard !covered.isEmpty else {
            let flow = pattern.components.map(\.name).joined(separator: " → ")
            return """
                Rewrite the rough talk below into a clean, deliverable speech, letting the \
                ideas flow in this order (guidance only — do not print these words): \(flow)

                Rough talk:
                \"\"\"
                \(transcript)
                \"\"\"

                Write it as one continuous speech in a confident first-person voice. Cut \
                filler and any off-topic asides (scheduling, small talk, logistics). Do not \
                invent anything, and do not use headings, labels, or bullet points.

                Speech:
                """
        }

        let points = covered
            .enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")

        return """
            Develop the following points into a polished, engaging speech, in this exact \
            order. REPHRASE and expand each point into natural spoken paragraphs — do not just \
            repeat or list them. Add a brief opening and closing and smooth transitions so it \
            flows as one speech. Keep every point's meaning, and add connective and rhetorical \
            phrasing to make it engaging, but do not add new facts, statistics, or examples \
            beyond the points. Write plain flowing paragraphs — no headings, labels, numbers, \
            or bullet points.

            Points:
            \(points)

            Speech:
            """
    }
}
