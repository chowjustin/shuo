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

    public var description: String {
        switch self {
        case .persuade: "The act of using spoken or nonverbal messages to influence an audience's beliefs, attitudes, or behaviors to convince listeners to voluntarily adopt a new perspective or take a specific action, without using force or manipulation."
        case .inspire: "To inspire in public speaking means to connect with your audience emotionally, shifting their mindset and moving them to action. Rather than just presenting facts, an inspirational speaker uses storytelling and shared values to spark enthusiasm, build trust, and empower listeners."
        case .inform: "To inform means to educate, enlighten, or teach your audience about a specific topic that aims to change beliefs or behaviors, the primary goal is to present objective facts, concepts, or processes clearly so the audience leaves with a deeper understanding."
        }
    }
}
