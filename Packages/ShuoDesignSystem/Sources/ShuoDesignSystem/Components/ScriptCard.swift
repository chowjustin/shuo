//
//  ScriptCard.swift
//  ShuoDesignSystem
//
//  Created by Gabriel Michelle Wibisono on 15/07/26.
//

import SwiftUI

public struct ScriptCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var badgeHorizontalPadding: CGFloat = 6
    @ScaledMetric(relativeTo: .caption2) private var badgeVerticalPadding: CGFloat = 3
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
                    
                    metaAndPurposeRow
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
    private var contentAlignment: VerticalAlignment {
        .bottom
    }

    private var isLargeTextLayout: Bool {
            dynamicTypeSize >= .xxxLarge
            
    }
        
        @ViewBuilder
            private var metaAndPurposeRow: some View {
                if isLargeTextLayout {
                    VStack(alignment: .leading, spacing: ShuoSpacing.small) {
                        dateAndDuration
                        purposeBadge
                    }
                } else {
                    HStack(spacing: 6) {
                        dateAndDuration
                        purposeBadge
                    }
                }
            }

            // xxxLarge–AX5: date and duration each get their own line, so they never
            // have to compete for horizontal space and can't wrap into each other.
            // Below that: single line with a dot separator, same as before.
            private var dateAndDuration: some View {
                Group {
                    if isLargeTextLayout {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateText)
                            HStack(spacing: 4) {
                                Text("•")
                                Text(durationText)
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(dateText)
                            Text("•")
                            Text(durationText)
                        }
                        .lineLimit(1)
                    }
                }
                .font(ShuoTypography.caption)
                .foregroundStyle(isSelected ? ShuoColor.secondaryTextPinkTint : ShuoColor.secondaryTextCream)
            }

            private var purposeBadge: some View {
                Text(purposeLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, badgeHorizontalPadding)
                    .padding(.vertical, badgeVerticalPadding)
                    .background(ShuoColor.aqua, in: .capsule)
                    .foregroundStyle(ShuoColor.primaryTextAqua)
            }
        }
