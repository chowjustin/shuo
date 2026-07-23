//
//  DeleteScriptUseCase.swift
//  ShuoCore
//
//  Created by rasyel on 23/07/26.
//


import Foundation
import ShuoCore

/// Deletes a script by its ID.
public struct DeleteScriptUseCase: Sendable {
    private let repository: any ScriptRepository

    public init(repository: any ScriptRepository) {
        self.repository = repository
    }

    public func callAsFunction(id: UUID) async throws {
        // Asumsi repository milikmu memiliki fungsi delete(id:). 
        // Jika belum, pastikan menambahkannya di protokol ScriptRepository.
        try await repository.delete(id: id)
    }
}