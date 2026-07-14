//
//  HomeView.swift
//  FeatureHome
//
//  Created by Justin Chow on 13/07/26.
//

import SwiftUI

public struct HomeView: View {
    private let onTapCreate: () -> Void

    public init(onTapCreate: @escaping () -> Void = {}) {
        self.onTapCreate = onTapCreate
    }

    public var body: some View {
        Text("Hello, World!")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onTapCreate) {
                        Image(systemName: "plus")
                    }
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
