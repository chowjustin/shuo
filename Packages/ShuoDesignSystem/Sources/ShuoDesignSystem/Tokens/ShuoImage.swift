//
//  ShuoImage.swift
//  ShuoDesignSystem
//

// Mascot image tokens, resolved from this package's asset catalog so package
// previews can find them without needing the main app bundle.

import SwiftUI

/// Mascot images, as semantic tokens.
///
/// Resolves against the `ShuoDesignSystem` bundle so the images are accessible
/// from any package preview — not just the app target.
public enum ShuoImage {

    // MARK: - Mascots

    public static let mascotAttach     = named("SHUO ATTACH")
    public static let mascotDefault    = named("SHUO DEFAULT")
    public static let mascotError      = named("SHUO ERROR")
    public static let mascotListen     = named("SHUO LISTEN")
    public static let mascotSleep      = named("SHUO SLEEP")
    public static let mascotTranscribe = named("SHUO TRANSCRIBE")
    public static let mascotWrite      = named("SHUO WRITE")

    // MARK: - Resolution

    private static func named(_ name: String) -> Image {
        Image(name, bundle: .module)
    }
}
