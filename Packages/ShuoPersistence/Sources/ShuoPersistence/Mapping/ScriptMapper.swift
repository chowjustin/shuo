//
//  ScriptMapper.swift
//  ShuoPersistence
//
//  Created by Justin Chow on 13/07/26.
//

// Maps `ScriptEntity` <-> `Script` in both directions. Exists so domain entities can
// stay plain `Sendable` structs, sidestepping SwiftData's Swift 6 actor-isolation sharp
// edges. See ARCHITECTURE.md §4.3.

import Foundation
