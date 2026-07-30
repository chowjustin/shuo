//
//  PatternCard.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import SwiftUI

public struct PatternCard: View {
    private let name: String
    private let summary: String
    private let isFocused: Bool
    private let isMostRecommended: Bool

    public init(
        name: String,
        summary: String,
        isFocused: Bool,
        isMostRecommended: Bool = false
    ) {
        self.name = name
        self.summary = summary
        self.isFocused = isFocused
        self.isMostRecommended = isMostRecommended
    }

    public var body: some View {
        // HANYA 1 LAYER DINAMIS: Akan mengubah ukurannya secara cerdas
        VStack(alignment: .center, spacing: 8) {
            Text(name)
                .font(isFocused ? .title3.bold() : ShuoTypography.headline)
                .foregroundStyle(ShuoColor.primaryTextAqua)
                .lineLimit(isFocused ? nil : 2)

            if isFocused {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(ShuoColor.secondaryTextAqua)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(width: 230)
        // KUNCI UTAMA: Memaksa layout mengecil/membesar memeluk teks persis!
        .fixedSize(horizontal: false, vertical: true)
        .cardStyle(isSelected: true, showsBorder: false)
        .scaleEffect(isFocused ? 1 : 0.85)
        .opacity(isFocused ? 1 : 0.3)
        // Animasi ini akan membuat pergerakan tinggi container (HStack) membesar dan mengecil secara halus
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isFocused ? "\(name). \(summary)" : name)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
    }

    private var accessibilityText: String {
        return isFocused ? "\(name). \(summary)" : name
    }

    private var focusedContent: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(name)
                .font(.title3.bold())
                .foregroundStyle(ShuoColor.primaryTextAqua)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary)
                .font(.caption)
                .foregroundStyle(ShuoColor.secondaryTextAqua)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    private var collapsedContent: some View {
        Text(name)
            .font(ShuoTypography.headline)
            .foregroundStyle(ShuoColor.primaryTextAqua)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 20) // Samakan padding agar rapi
    }
}
