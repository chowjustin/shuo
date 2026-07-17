//
//  HomeView.swift
//  FeatureHome
//
//  Created by Justin Chow on 13/07/26.
//
 
import SwiftUI
import ShuoDesignSystem

public struct HomeView: View {
    private let onTapCreate: () -> Void
    @State private var searchText: String = ""

    public init(onTapCreate: @escaping () -> Void = {}) {
        self.onTapCreate = onTapCreate
    }

    public var body: some View {
        ZStack {
            Color(ShuoColor.background)
                .ignoresSafeArea()
            
            if searchText.isEmpty {
                Text("No scripts yet.")
                    .accessibilityLabel("No scripts yet. Start creating one!")
                    .fontWeight(.light)
                    .foregroundStyle(Color(ShuoColor.primaryText))
            } else {
                Text("Scripts not found.")
                    .fontWeight(.light)
                    .foregroundStyle(Color(ShuoColor.secondaryText))
            }
        }
        .navigationTitle("All Scripts")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onTapCreate) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(ShuoColor.pink)
                .accessibilityLabel("New script")
                }
            }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
