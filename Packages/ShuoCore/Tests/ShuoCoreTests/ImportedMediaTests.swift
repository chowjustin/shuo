//
//  ImportedMediaTests.swift
//  ShuoCoreTests
//

import Testing
import Foundation
@testable import ShuoCore

@Suite("ImportedMedia")
struct ImportedMediaTests {

    private let url = URL(filePath: "/tmp/test.m4a")

    @Test("formattedDuration is nil when duration is nil")
    func formattedDurationNilWhenNoDuration() {
        let media = ImportedMedia(fileURL: url, kind: .audio, originalFileName: "test.m4a")
        #expect(media.formattedDuration == nil)
    }

    @Test("formattedDuration is nil when duration is zero")
    func formattedDurationNilWhenZero() {
        let media = ImportedMedia(fileURL: url, kind: .audio, originalFileName: "test.m4a", duration: 0)
        #expect(media.formattedDuration == nil)
    }

    @Test("formattedDuration formats minutes, padded seconds, and one decimal")
    func formattedDurationFormatsCorrectly() {
        let media = ImportedMedia(fileURL: url, kind: .audio, originalFileName: "test.m4a", duration: 83.7)
        #expect(media.formattedDuration == "1:23.7")
    }

    @Test("formattedDuration pads seconds under 10 with leading zero")
    func formattedDurationPadsSeconds() {
        let media = ImportedMedia(fileURL: url, kind: .audio, originalFileName: "test.m4a", duration: 5.3)
        #expect(media.formattedDuration == "0:05.3")
    }

    @Test("formattedDuration handles exact minute boundary")
    func formattedDurationExactMinute() {
        let media = ImportedMedia(fileURL: url, kind: .audio, originalFileName: "test.m4a", duration: 60.0)
        #expect(media.formattedDuration == "1:00.0")
    }

    @Test("formattedDuration works for video kind")
    func formattedDurationVideo() {
        let media = ImportedMedia(fileURL: url, kind: .video, originalFileName: "test.mp4", duration: 125.5)
        #expect(media.formattedDuration == "2:05.5")
    }

    @Test("formattedDuration is nil for PDF")
    func formattedDurationPDFNil() {
        let media = ImportedMedia(fileURL: url, kind: .pdf, originalFileName: "test.pdf", duration: nil)
        #expect(media.formattedDuration == nil)
    }
}
