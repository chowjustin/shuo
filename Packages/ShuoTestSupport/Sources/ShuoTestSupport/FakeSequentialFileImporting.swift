//
//  FakeSequentialFileImporting.swift
//  ShuoTestSupport
//

import Foundation
import ShuoCore

/// A test double that returns a different result on each successive call to `importFile`.
/// Useful for testing file-overwrite scenarios where the same importer is called twice.
public actor FakeSequentialFileImporting: FileImporting {
    private let results: [Result<ImportedMedia, any Error>]
    private var callIndex = 0

    public init(results: [Result<ImportedMedia, any Error>]) {
        self.results = results
    }

    public func importFile(from url: URL) async throws -> ImportedMedia {
        defer { callIndex += 1 }
        let index = min(callIndex, results.count - 1)
        return try results[index].get()
    }
}
