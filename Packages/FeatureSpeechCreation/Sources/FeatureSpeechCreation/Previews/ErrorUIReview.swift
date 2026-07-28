// ErrorUIReview.swift
// TEMPORARY — delete this file once all error-state UIs have been visually approved.
//
// Covers error states that are in use:
//   A. Speak Mode   — inline panel (inside the input screen, not a sheet)
//   B. Loading      — ErrorSheet after the user taps ✓
//   E. Analysis     — ErrorSheet during / after AI analysis
//
// Open Xcode Canvas and step through each named preview variant.

#if DEBUG
import ShuoDesignSystem
import SwiftUI

// ─────────────────────────────────────────────
// A. SPEAK MODE — Inline panel errors
//    These appear inside SpeakModeView, not as a sheet.
// ─────────────────────────────────────────────

#Preview("A1 · Speak — Audio not detected") {
    speakPanel(message: "We couldn't detect any audio. Try speaking closer to the mic.")
}

#Preview("A2 · Speak — Storage full") {
    speakPanel(message: "Your device storage is full. Free up some space and try again.")
}

// ─────────────────────────────────────────────
// B. LOADING ROUTE — ErrorSheet (TranscriptionErrorCopy)
//    Appears after the user taps ✓ and transcription fails.
// ─────────────────────────────────────────────

#Preview("B01 · Loading — File too large") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "File too large.",
        message: "Maximum file size: 250 MB"
    )
}

#Preview("B02 · Loading — Recording too long") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "Recording too long.",
        message: "Shuo can work with speeches up to 30 minutes. Try a shorter clip."
    )
}

#Preview("B03 · Loading — Too short") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "That's too short to work with.",
        message: "Shuo needs at least 3 seconds of speech to suggest a structure. Go back and add a little more."
    )
}

#Preview("B10 · Loading — Transcription failed (generic)") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "Transcription failed.",
        message: "Something went wrong while reading this file. Please try again."
    )
}

// ─────────────────────────────────────────────
// E. ANALYSIS — ErrorSheet (AnalysisErrorCopy)
//    Appears on the analysis screen when AI fails.
// ─────────────────────────────────────────────

#Preview("E01 · Analysis — Not enough content") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "There isn't enough here yet.",
        message: "We need a bit more of your speech before we can suggest a structure. Try again with a longer draft."
    )
}

#Preview("E02 · Analysis — Mostly silence") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "We couldn't hear any speech.",
        message: "This recording seems to be silent, or contains only background noise. Try recording again somewhere quieter."
    )
}

#Preview("E08 · Analysis — Speech too long for context") {
    ErrorSheet(
        mascotImageName: "SHUO ERROR",
        title: "That speech is a bit too long.",
        message: "There's more here than we can analyze in one pass. Try again with a shorter section."
    )
}

// ─────────────────────────────────────────────
// MARK: - Local view builders
// ─────────────────────────────────────────────

/// Recreates the inline panel from `SpeakModeView.messagePanel()`.
private func speakPanel(message: String, actionLabel: String? = nil) -> some View {
    VStack(spacing: ShuoSpacing.medium) {
        ShuoImage.mascotError
            .resizable()
            .scaledToFit()
            .frame(width: 180, height: 180)

        Text(message)
            .foregroundStyle(ShuoColor.secondaryTextCream)
            .multilineTextAlignment(.center)
            .padding(.horizontal, ShuoSpacing.xLarge)

        if let actionLabel {
            Button(actionLabel) {}
                .font(.subheadline.bold())
                .foregroundStyle(ShuoColor.pink)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuoColor.background)
}
#endif
