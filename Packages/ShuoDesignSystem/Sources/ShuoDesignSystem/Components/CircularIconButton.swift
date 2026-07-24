//
//  CircularIconButton.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 21/07/26.
//

import SwiftUI

/// The single, unmissable action at the bottom of an Input Script mode — attach a file,
/// start recording, pause.
///
/// One component rather than per-mode shapes: the modes sit behind a segmented control,
/// so their primary buttons are compared directly by switching tabs. Any difference in
/// size or shape between them reads as a difference in meaning.
///
/// Takes only primitives (an SF Symbol name, an emphasis, a closure) so it stays free of
/// domain types and previewable in isolation (CLAUDE.md §4).
public struct CircularIconButton: View {
    /// How much weight the button carries in its current state.
    ///
    /// `.filled` is the go-forward action; `.outlined` is the same action mid-flight
    /// (pausing a recording), quieter but still clearly the same control.
    public enum Emphasis: Sendable {
        case filled
        case outlined
    }

    private static let diameter: CGFloat = 72

    private let systemImage: String
    private let emphasis: Emphasis
    private let accessibilityTitle: String
    private let action: () -> Void

    public init(
        systemImage: String,
        emphasis: Emphasis = .filled,
        accessibilityTitle: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.accessibilityTitle = accessibilityTitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(emphasis == .filled ? ShuoColor.pink : ShuoColor.background)

                if emphasis == .outlined {
                    Circle().stroke(ShuoColor.pink, lineWidth: 2)
                }

                Image(systemName: systemImage)
                    .font(.largeTitle.bold())
                    .foregroundStyle(emphasis == .filled ? Color.white : ShuoColor.pink)
            }
            .frame(width: Self.diameter, height: Self.diameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }
}
