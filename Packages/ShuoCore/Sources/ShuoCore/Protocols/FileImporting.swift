//
//  FileImporting.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain protocol: `FileImporting` — importFile(from:) async throws -> ImportedMedia.
// Implemented by `FileImportService` in ShuoAudio, which handles the security-scoped
// resource copy into the sandbox. See ARCHITECTURE.md §3.1.5.

import Foundation
