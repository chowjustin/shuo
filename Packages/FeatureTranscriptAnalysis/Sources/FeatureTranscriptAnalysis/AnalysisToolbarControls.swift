//
//  AnalysisToolbarControls.swift
//  FeatureTranscriptAnalysis
//

import Foundation

/// Which controls the analysis screen's toolbar offers.
///
/// Derived from the screen's state and expressed as a value so the rule can be asserted in
/// a unit test rather than only being visible by reading the view. This screen shipped
/// twice with an unconditional pair of buttons, which put a permanently-disabled one next
/// to a spinner and next to error sheets — a disabled button is still a button, and it
/// invites a tap that answers with nothing.
public struct AnalysisToolbarControls: Equatable, Sendable {

    /// ‹ — back to Input Script, with the recording and every mode as the user left them.
    public let showsBack: Bool

    /// ✓ — done with this screen. Prompts about unsaved changes on the way out; it is not
    /// a bare save button.
    public let showsFinish: Bool

    /// - Parameters:
    ///   - state: what the screen is currently showing.
    ///   - canReturnToInput: whether there is an Input Script step behind this one. False
    ///     for a script reopened from the library, which was opened directly onto analysis
    ///     and has no earlier step to return to.
    public init(state: TranscriptAnalysisViewState, canReturnToInput: Bool) {
        showsBack = canReturnToInput

        // A screen that is still analyzing, or has failed, has nothing worth finishing —
        // *unless* ✓ is the only door. Reopened from the library there is no ‹, so ✓ is
        // always offered there and reads as "leave"; the unsaved-changes prompt behind it
        // covers the rest either way.
        showsFinish = state == .loaded || !canReturnToInput
    }
}
