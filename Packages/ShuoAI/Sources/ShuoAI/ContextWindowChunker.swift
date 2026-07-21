//
//  ContextWindowChunker.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Chunk/condense strategy for transcripts that could exceed
// `SystemLanguageModel.default.contextSize`. In scope for v1, not a later hardening
// pass — route any long transcript through here rather than sending it raw into a
// prompt (CLAUDE.md §8).

import Foundation

/// Keeps transcripts inside the model's context window.
///
/// Two strategies, because the two calls need different things from a long transcript:
///
/// - **Classification** needs to recognize the *shape* of the speech, which the opening
///   and closing carry disproportionately — an introduction states the topic, a conclusion
///   states the takeaway. `condensed` keeps both ends and drops the middle.
/// - **Key-point extraction** needs the whole thing, since content for a late component
///   lives in late text. `chunks` splits it so each part can be extracted separately and
///   the results merged.
///
/// Pure and deterministic: no model calls, so it is cheap to test exhaustively.
struct ContextWindowChunker {

    /// Characters per token, used to convert the model's token-denominated context size
    /// into a character budget. English prose runs roughly 4 characters per token; 3.5 is
    /// deliberately pessimistic, since underestimating costs a little wasted window and
    /// overestimating costs a failed generation.
    static let charactersPerToken = 3.5

    /// Tokens held back for instructions, the schema, and the response itself. The prompt
    /// is only one part of what has to fit.
    static let reservedTokens = 1_500

    /// Maximum characters of transcript that may go into a single prompt.
    let budget: Int

    /// - Parameter contextSize: `SystemLanguageModel.default.contextSize`, in tokens.
    init(contextSize: Int) {
        let usableTokens = max(contextSize - Self.reservedTokens, Self.minimumUsableTokens)
        self.budget = Int(Double(usableTokens) * Self.charactersPerToken)
    }

    /// Direct budget, for tests.
    init(budget: Int) {
        self.budget = max(budget, 1)
    }

    /// A floor so an unexpectedly small reported context size can't produce a zero or
    /// negative budget and jam the flow entirely.
    private static let minimumUsableTokens = 512

    /// True when `transcript` needs any of this at all — the common case is that it
    /// doesn't.
    func exceedsBudget(_ transcript: String) -> Bool {
        transcript.count > budget
    }

    /// The transcript unchanged when it fits; otherwise its opening and closing joined by
    /// an elision marker.
    ///
    /// The marker is spelled out in words rather than left as an ellipsis so the model
    /// reads it as a statement about the text rather than as something the speaker said.
    func condensed(_ transcript: String) -> String {
        guard exceedsBudget(transcript) else { return transcript }

        let marker = "\n\n[... middle of the transcript omitted for length ...]\n\n"
        let available = max(budget - marker.count, 2)
        // Weighted toward the opening, which carries the topic statement and usually the
        // clearest signal of how the speech is organized.
        let headLength = available * 2 / 3
        let tailLength = available - headLength

        let head = String(transcript.prefix(headLength))
        let tail = String(transcript.suffix(tailLength))
        return head + marker + tail
    }

    /// The transcript split into budget-sized pieces, broken at whitespace so no word is
    /// cut in half.
    ///
    /// Returns a single element when the transcript already fits, so callers need no
    /// special case for the common path.
    func chunks(_ transcript: String) -> [String] {
        guard exceedsBudget(transcript) else { return [transcript] }

        var chunks: [String] = []
        var current = ""

        for word in transcript.split(whereSeparator: \.isWhitespace) {
            // A single word longer than the whole budget can't be placed; hard-splitting
            // it would corrupt it, and it can't be language anyway, so drop it rather than
            // loop forever.
            guard word.count <= budget else { continue }

            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= budget {
                current += " " + word
            } else {
                chunks.append(current)
                current = String(word)
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks.isEmpty ? [transcript] : chunks
    }
}
