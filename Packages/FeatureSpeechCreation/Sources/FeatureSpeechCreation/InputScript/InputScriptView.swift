//
//  InputScriptView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import ShuoCore
import ShuoDesignSystem
import SwiftUI

public struct InputScriptView: View {
    @Bindable private var viewModel: InputScriptViewModel
    private let onBack: () -> Void
    private let onClose: () -> Void
    @FocusState private var isTitleFocused: Bool

    public init(
        viewModel: InputScriptViewModel,
        onBack: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Title", text: $viewModel.title)
                        .font(.system(.largeTitle, weight: .bold))
                        .focused($isTitleFocused)

                    HStack(spacing: 8) {
                        Text("Purpose:")
                            .font(.headline)
                        Text(viewModel.purpose.title)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ShuoColor.cardBackground, in: Capsule())
                    }

                    Picker("Input Mode", selection: $viewModel.mode) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Spacer()
                        modeContent
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { isTitleFocused = false }
                .navigationTitle("Input Script")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            .blur(radius: viewModel.attachVM.isFileTooLarge ? 8 : 0)
            .animation(.spring(duration: 0.25), value: viewModel.attachVM.isFileTooLarge)

            if viewModel.attachVM.isFileTooLarge {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                fileTooLargeAlert
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: viewModel.attachVM.isFileTooLarge)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(true)
    }

    private var fileTooLargeAlert: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red.opacity(0.85))

            Text("File too large.")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text("Maximum file size: 20MB")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                viewModel.attachVM.cancel()
                viewModel.attachVM.isPickerPresented = true
            } label: {
                Text("Try again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
        .frame(width: 300)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch viewModel.mode {
        case .attachFile:
            AttachFileModeView(viewModel: viewModel.attachVM)
        case .speak:
            Text("Let's hear your ideas.")
        case .write:
            Text("Let's write your ideas.")
        }
    }
}

#Preview {
    InputScriptPreviewHost()
}

private struct PreviewFileImporter: FileImporting {
    func importFile(from url: URL) async throws -> ImportedMedia {
        ImportedMedia(fileURL: url, kind: .audio, originalFileName: url.lastPathComponent)
    }
}

private struct InputScriptPreviewHost: View {
    @State private var isPresented = true

    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                InputScriptView(
                    viewModel: InputScriptViewModel(
                        purpose: .persuade,
                        fileImporter: PreviewFileImporter()
                    ),
                    onBack: {},
                    onClose: { isPresented = false }
                )
            }
    }
}
