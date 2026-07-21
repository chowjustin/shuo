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
    @State private var selectedID: Int? = nil

        // ini masih Placeholder sample data — replace with real ScriptSummary array later 
        private let sampleScripts = [
            (id: 0, title: "Why must join campus organization", date: "3 July 2026", duration: "15:10:40", purpose: "To Persuade"),
            (id: 1, title: "How volunteering changed my life", date: "28 June 2026", duration: "08:42:10", purpose: "To Inspire"),
            (id: 2, title: "Understanding climate policy", date: "15 June 2026", duration: "12:05:33", purpose: "To Inform")
        ]
    
    public init(onTapCreate: @escaping () -> Void = {}) {
        self.onTapCreate = onTapCreate
    }

    public var body: some View {
        ZStack {
            Color(ShuoColor.background)
                .ignoresSafeArea()
            
            if sampleScripts.isEmpty {
                Text("No scripts yet.")
                    .accessibilityLabel("No scripts yet. Start creating one!")
                    .fontWeight(.light)
                    .foregroundStyle(Color(ShuoColor.primaryText))
            } else {
                List {
                                    ForEach(sampleScripts, id: \.id) { script in
                                        ScriptCard(
                                            title: script.title,
                                            dateText: script.date,
                                            durationText: script.duration,
                                            purposeLabel: script.purpose,
                                            isSelected: selectedID == script.id,
                                            onTap: { selectedID = script.id }
                                        )
                                        .listRowInsets(EdgeInsets(top: 0, leading: ShuoSpacing.medium, bottom: ShuoSpacing.medium, trailing: ShuoSpacing.medium))
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
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
//                Text("Scripts not found.")
//                    .fontWeight(.light)
//                    .foregroundStyle(Color(ShuoColor.secondaryText))
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
