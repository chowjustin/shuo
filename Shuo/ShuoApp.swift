//
//  ShuoApp.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

// App entry point (@main). Builds the AppContainer composition root and shows
// FeatureHome.HomeView as the root view inside a NavigationStack — see
// ARCHITECTURE.md §12.1.

import SwiftUI

@main
struct ShuoApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                container.makeHomeView()
            }
        }
    }
}
