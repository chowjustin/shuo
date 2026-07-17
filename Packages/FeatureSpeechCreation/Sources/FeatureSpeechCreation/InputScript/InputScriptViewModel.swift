//
//  InputScriptViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Observation
import ShuoCore

@Observable
@MainActor
public final class InputScriptViewModel {
    public var title: String = ""
    public let purpose: SpeechPurpose
    public var mode: InputMode = .speak

    public let attachVM: AttachFileModeViewModel
    public let writeVM: WriteModeViewModel

    /// `true` when the currently active mode has enough content to proceed.
    public var hasValidContent: Bool {
        switch mode {
        case .speak:
            return false // SpeakModeViewModel not yet wired; always false for now.
        case .write:
            return writeVM.hasValidContent
        case .attachFile:
            return attachVM.hasImportedFile
        }
    }

    public init(purpose: SpeechPurpose, fileImporter: any FileImporting) {
        self.purpose = purpose
        self.attachVM = AttachFileModeViewModel(fileImporter: fileImporter)
        self.writeVM = WriteModeViewModel()
    }
}
