//
//  PillButton.swift
//  ShuoDesignSystem
//

import SwiftUI

/// The quieter action alongside an Input Script mode's primary control — reuploading a
/// file, retaking a recording.
///
/// One component rather than a capsule hand-rolled per mode: the modes sit behind a
/// segmented control and are compared directly by switching tabs, so "replace what I
/// already gave you" has to look identical in each of them. `CircularIconButton` is the
/// counterpart for the primary action.
///
/// Takes only primitives (a title and a closure) so it stays free of domain types and
/// previewable in isolation (CLAUDE.md §4).
public struct PillButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(ShuoColor.pink)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Capsule().stroke(ShuoColor.pink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: ShuoSpacing.large) {
        PillButton("Retake") {}
        PillButton("Reupload File") {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuoColor.background)
}
