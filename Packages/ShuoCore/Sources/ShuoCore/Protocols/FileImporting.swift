//
//  FileImporting.swift
//  ShuoCore
//

import Foundation

public protocol FileImporting: Sendable {
    func importFile(from url: URL) async throws -> ImportedMedia
}
