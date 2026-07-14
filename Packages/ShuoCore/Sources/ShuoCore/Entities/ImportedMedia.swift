//
//  ImportedMedia.swift
//  ShuoCore
//

import Foundation

public struct ImportedMedia: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case audio
        case video
        case pdf
    }

    public let id: UUID
    public let fileURL: URL
    public let kind: Kind
    public let originalFileName: String

    public init(id: UUID = UUID(), fileURL: URL, kind: Kind, originalFileName: String) {
        self.id = id
        self.fileURL = fileURL
        self.kind = kind
        self.originalFileName = originalFileName
    }
}
