//
//  AccordionView.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Reusable expand/collapse section, used by the Transcript view's Original/Refined
// sections. Expand/collapse state is ephemeral `@State` owned by the caller, not
// persisted. See ARCHITECTURE.md §3.2.2.

import Foundation
import SwiftUI

public struct AccordionView<Content: View>: View {
    private let title: String
    private let content: () -> Content
 
    public init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }
 
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ShuoTypography.headline)
                .foregroundStyle(ShuoColor.primaryText)
                .padding(ShuoSpacing.medium)
 
            content()
                .padding(.horizontal, ShuoSpacing.medium)
                .padding(.bottom, ShuoSpacing.medium)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ShuoColor.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ShuoColor.pink, lineWidth: 2)
        )
    }
}
 
#Preview {
    AccordionView(title: "Original Transcript") {
        Text("Some transcript content goes here.")
            .font(ShuoTypography.body)
            .foregroundStyle(ShuoColor.primaryText)
    }
    .padding()
}
 
