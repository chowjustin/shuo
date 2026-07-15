//
//  RootView.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

import FeatureHome
import FeatureSpeechCreation
import SwiftUI

struct RootView: View {
    let container: AppContainer
    @State private var coordinator: CreateScriptCoordinator?

    var body: some View {
        container.makeHomeView(onTapCreate: {
            coordinator = container.makeCreateScriptCoordinator(onFinish: { coordinator = nil })
        })
        .sheet(isPresented: isShowingCreateFlow) {
            if let coordinator {
                container.makePurposeSelectionView(coordinator: coordinator)
            }
        }
    }

    private var isShowingCreateFlow: Binding<Bool> {
        Binding(
            get: { coordinator != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator = nil
                }
            }
        )
    }
}
