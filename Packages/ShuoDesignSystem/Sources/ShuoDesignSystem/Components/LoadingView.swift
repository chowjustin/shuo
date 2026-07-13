//
//  LoadingView.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Shared loading screen reused across extraction/transcription/analysis and the
// 'waiting for model' state. Reads a display model (icon/message) rather than
// `ShuoCore.LoadingContext` directly, keeping this package domain-agnostic. See
// ARCHITECTURE.md §3.1.1, CLAUDE.md §4.

import Foundation
