//
//  FakeFileImporting.swift
//  ShuoTestSupport
//

import Foundation
import ShuoCore

public struct FakeFileImporting: FileImporting {
    private let result: Result<ImportedMedia, any Error>

    public init(returning media: ImportedMedia) {
        result = .success(media)
    }

    public init(throwing error: any Error) {
        result = .failure(error)
    }

    public func importFile(from _: URL) async throws -> ImportedMedia {
        try result.get()
    }
}
