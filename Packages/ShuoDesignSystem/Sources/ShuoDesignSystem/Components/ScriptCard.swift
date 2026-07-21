//
//  ScriptCard.swift
//  ShuoDesignSystem
//
//  Created by Gabriel Michelle Wibisono on 15/07/26.
//

import SwiftUI

struct ScriptCard: View {
    let title: String
    let dateText: String
    let durationText: String
    let purposeLabel: String
    var isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : ShuoColor.primaryText)
//                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(dateText)
                        Text("•")
                        Text(durationText)
                        purposeBadge
                    }
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : ShuoColor.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(isSelected ? .white : ShuoColor.secondaryText)
            }
            .padding(20) //buat atur besar cardnya (diatur dr paddingnya)
            .background(
                isSelected ? ShuoColor.pink : ShuoColor.pinkTint,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ShuoColor.pink, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var purposeBadge: some View {
        Text(purposeLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ShuoColor.aquaTint, in: .capsule)
            .foregroundStyle(ShuoColor.primaryText)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isSelected = false

        var body: some View {
            ScriptCard(
                title: "Why must join campus organization",
                dateText: "3 July 2026",
                durationText: "15:10:40",
                purposeLabel: "To Persuade",
                isSelected: isSelected,
                onTap: { isSelected.toggle() }
            )
            .padding()
//            .background(ShuoColor.background)
        }
    }
    return PreviewWrapper()
}
