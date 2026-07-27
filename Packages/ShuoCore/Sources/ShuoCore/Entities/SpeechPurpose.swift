//
//  SpeechPurpose.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `SpeechPurpose` enum (persuade / inspire / inform), the three static
// options the Purpose screen renders. See ARCHITECTURE.md §3.1.1.
// Pure Foundation, Sendable, Codable, CaseIterable — no Apple-SDK imports (CLAUDE.md §4).

import Foundation
public enum SpeechPurpose: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case persuade
    case inspire
    case inform

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .persuade: "To Persuade"
        case .inspire: "To Inspire"
        case .inform: "To Inform"
        }
    }

    /// The purpose as a gerund — "Persuading", "Inspiring", "Informing" — for composing
    /// running text such as the Input Script sheet's "Input Persuading Script" title.
    /// English-only, matching v1's scope (ARCHITECTURE.md §2.3).
    public var gerund: String {
        switch self {
        case .persuade: "Persuading"
        case .inspire: "Inspiring"
        case .inform: "Informing"
        }
    }

    public var description: String {
        switch self {
        case .persuade: "Using spoken or nonverbal messages to ethically influence beliefs or behavior, persuading an audience to voluntarily change perspective or act."
        case .inspire: "To connect emotionally with your audience, shifting their mindset and action using storytelling and shared values rather than just facts."
        case .inform: "To educate or teach your audience about a topic, presenting objective facts, concepts, or processes clearly so listeners leave with a deeper understanding."
        }
    }
}
