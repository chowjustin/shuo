//
//  FileImportService.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// Conforms to `FileImporting` (ShuoCore). Handles the security-scoped resource lifecycle
// (`startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource`) and
// copies the picked file into the app sandbox before further processing. See
// ARCHITECTURE.md §3.1.5.

import Foundation
