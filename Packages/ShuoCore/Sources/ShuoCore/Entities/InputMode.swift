//
//  InputMode.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation

public enum InputMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case attachFile
    case speak
    case write

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .attachFile: "Attach Files"
        case .speak: "Speak"
        case .write: "Write"
        }
    }
}
