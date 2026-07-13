//
//  GeneratedContentMapper.swift
//  ShuoAI
//
//  Created by Justin Chow on 13/07/26.
//

// Maps every `@Generable` DTO in Schemas/ to its `ShuoCore` domain entity. Keeps the
// macro-generated schema out of the domain layer entirely — Feature packages and
// ViewModels only ever see `SpeechPattern`, `KeyPoint`, etc. See ARCHITECTURE.md §3.2.4.

import Foundation
