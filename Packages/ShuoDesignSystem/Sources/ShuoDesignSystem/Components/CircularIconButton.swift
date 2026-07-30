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

    // Base sizes at the default (non-scaled) content size category.
    // Both are tied to the same Dynamic Type curve so the icon and its
    // circle always grow together — this is the actual fix (see note below).
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 28

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
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(emphasis == .filled ? Color.white : ShuoColor.pink)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }
}

#Preview {
    VStack(spacing: ShuoSpacing.xLarge) {
        CircularIconButton(systemImage: "paperclip", accessibilityTitle: "Attach a file") {}
        CircularIconButton(systemImage: "mic.fill", accessibilityTitle: "Start recording") {}
        CircularIconButton(
            systemImage: "pause.fill",
            emphasis: .outlined,
            accessibilityTitle: "Pause recording"
        ) {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuoColor.background)
}
