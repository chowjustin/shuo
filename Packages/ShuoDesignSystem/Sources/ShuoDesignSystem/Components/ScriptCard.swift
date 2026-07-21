//
//  ScriptCard.swift
//  ShuoDesignSystem
//
//  Created by Gabriel Michelle Wibisono on 15/07/26.
//

import SwiftUI

public struct ScriptCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let dateText: String
    private let durationText: String
    private let purposeLabel: String
    private let isSelected: Bool
    private let onTap: () -> Void
    
    public init(
        title: String,
        dateText: String,
        durationText: String,
        purposeLabel: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.dateText = dateText
        self.durationText = durationText
        self.purposeLabel = purposeLabel
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(alignment: .bottom, spacing: ShuoSpacing.small) {
                VStack(alignment: .leading, spacing: ShuoSpacing.small) {
                    Text(title)
                        .font(ShuoTypography.headline)
                        .foregroundStyle(isSelected ? ShuoColor.primaryTextPinkTint : ShuoColor.primaryTextCream)
                    
                    HStack(spacing: 6) {
                        Text(dateText)
                        Text("•")
                        Text(durationText)
                        purposeBadge
                    }
                    .font(ShuoTypography.caption)
                    .foregroundStyle(isSelected ? ShuoColor.secondaryTextPinkTint : ShuoColor.secondaryTextCream)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(ShuoColor.pink)
            }
            .padding(20) //buat atur besar cardnya
            .background(
                isSelected ? ShuoColor.pinkTint : ShuoColor.background,
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(ShuoColor.pink, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private var purposeBadge: some View {
        Text(purposeLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ShuoColor.aqua, in: .capsule)
            .foregroundStyle(ShuoColor.primaryText)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isSelected = false

        var body: some View {
            List {
                ScriptCard(
                            title: "Why must join campus organization",
                            dateText: "3 July 2026",
                            durationText: "15:10:40",
                            purposeLabel: "To Persuade",
                            isSelected: isSelected,
                            onTap: { isSelected.toggle() }
                        )
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    print("delete tapped — not wired to real data yet")
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
//        .background(ShuoColor.background)
                            
        }
    }
    return PreviewWrapper()
}
