//
//  GeneratedPatternSet.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// `@Generable` DTO: wraps `[GeneratedPattern]` with `@Guide(.count(3))` to force exactly
// 3 patterns back from the model. Never exposed outside ShuoAI — `GeneratedContentMapper`
// converts it to `ShuoCore.SpeechPattern`. See ARCHITECTURE.md §3.2.4, CLAUDE.md §8.

import Foundation
