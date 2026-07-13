//
//  ContextWindowChunker.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Chunk/summarize-then-analyze strategy for transcripts that could exceed
// `SystemLanguageModel.default.contextSize`. In scope for v1, not a later hardening
// pass — route any long transcript through here rather than sending it raw into a
// prompt (CLAUDE.md §8).

import Foundation
