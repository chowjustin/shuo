//
//  HomeView.swift
//  FeatureHome
//
//  Created by Justin Chow on 13/07/26.
//
 
import Foundation
import ShuoCore
import ShuoDesignSystem
import SwiftUI

public struct HomeView: View {
    @Bindable private var viewModel: HomeViewModel
    private let onTapCreate: () -> Void
    private let onSelectScript: (ScriptSummary.ID) -> Void

    @State private var selectedID: ScriptSummary.ID?

    @State private var scriptToDelete: ScriptSummary?
    @State private var showDeleteAlert = false

    public init(
        viewModel: HomeViewModel,
        onTapCreate: @escaping () -> Void = {},
        onSelectScript: @escaping (ScriptSummary.ID) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onTapCreate = onTapCreate
        self.onSelectScript = onSelectScript
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(ShuoColor.primaryTextCream)]
        appearance.titleTextAttributes = [.foregroundColor: UIColor(ShuoColor.primaryTextCream)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    public var body: some View {
        ZStack {
            ShuoColor.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                customSearchBar
                content
            }
        }
        .navigationTitle("All Scripts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onTapCreate) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(ShuoColor.pink)
                .accessibilityLabel("New script")
            }
        }
        .onAppear {
            viewModel.load()
        }
        .alert(
            "Delete Script",
            isPresented: $showDeleteAlert,
            presenting: scriptToDelete
        ) { script in
            Button("Cancel", role: .cancel) {
                scriptToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.delete(id: script.id)
                scriptToDelete = nil
            }
        } message: { script in
            Text("Are you sure you want to delete \"\(script.title)\"? This action cannot be undone.")
        }
    }

    // MARK: - Custom Search Bar
    private var customSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search", text: $viewModel.searchQuery)
                .foregroundStyle(ShuoColor.primaryText)
                .submitLabel(.search)
                .autocorrectionDisabled()
            
            if !viewModel.searchQuery.isEmpty {
                Button(action: { viewModel.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemGray6))
        )
        .padding(.horizontal, ShuoSpacing.medium)
        .padding(.vertical, ShuoSpacing.small)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            emptyStateView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let summaries):
            List {
                ForEach(summaries) { summary in
                    ScriptCard(
                        title: summary.title,
                        dateText: summary.createdAt.formatted(date: .abbreviated, time: .omitted),
                        durationText: summary.recordingDuration.map(formattedDuration) ?? "—",
                        purposeLabel: summary.purpose.title,
                        isSelected: selectedID == summary.id,
                        onTap: {
                            selectedID = summary.id
                            onSelectScript(summary.id)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: ShuoSpacing.small, leading: ShuoSpacing.medium, bottom: ShuoSpacing.small, trailing: ShuoSpacing.medium))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel(summary.title)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        
                        Button(role: .destructive) {
                            scriptToDelete = summary
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyStateView: some View {
        let isSearching = !viewModel.searchQuery.isEmpty

        return Text(isSearching ? "No results for \"\(viewModel.searchQuery)\"." : "No scripts yet. Start inputting a new script!")
            .accessibilityLabel(isSearching ? "No results for \(viewModel.searchQuery)." : "No scripts yet. Start inputting a new script!")
            .font(ShuoTypography.body)
            .fontWeight(.light)
            .foregroundStyle(ShuoColor.secondaryTextCream)
            .multilineTextAlignment(.center)
            .padding(ShuoSpacing.large)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? ""
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                fetchScriptSummaries: FetchScriptSummariesUseCase(repository: PreviewScriptRepository(hasScripts: true)),
                searchScripts: SearchScriptsUseCase(repository: PreviewScriptRepository(hasScripts: true)),
                // 👇 Inject DeleteScriptUseCase di Preview
                deleteScript: DeleteScriptUseCase(repository: PreviewScriptRepository(hasScripts: true))
            ),
            onSelectScript: { id in
                print("Selected script ID: \(id)")
            }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                fetchScriptSummaries: FetchScriptSummariesUseCase(repository: PreviewScriptRepository(hasScripts: false)),
                searchScripts: SearchScriptsUseCase(repository: PreviewScriptRepository(hasScripts: false)),
                deleteScript: DeleteScriptUseCase(repository: PreviewScriptRepository(hasScripts: false))
            )
        )
    }
}

private struct PreviewScriptRepository: ScriptRepository {
    let hasScripts: Bool

    func save(_ script: Script) async throws {}
    func fetch(id: UUID) async throws -> Script? { nil }
    
    func delete(id: UUID) async throws {
        print("Preview: Script \(id) deleted")
    }

    func fetchSummaries() async throws -> [ScriptSummary] {
        guard hasScripts else { return [] }
        return [
            ScriptSummary(id: UUID(), title: "Why must join campus organization", purpose: .persuade, createdAt: .now, recordingDuration: 245),
            ScriptSummary(id: UUID(), title: "How volunteering changed my life", purpose: .inspire, createdAt: .now, recordingDuration: 130),
            ScriptSummary(id: UUID(), title: "Understanding climate policy", purpose: .inform, createdAt: .now, recordingDuration: nil),
        ]
    }

    func search(query: String) async throws -> [ScriptSummary] {
        let all = try await fetchSummaries()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}
