import Testing
import Foundation
@testable import DualVideo

// MARK: - OutputResolution Tests

@Suite("OutputResolution")
struct OutputResolutionTests {

    @Test func hd720pWidth() {
        #expect(OutputResolution.hd720p.width == 720)
    }

    @Test func hd720pHeight() {
        #expect(OutputResolution.hd720p.height == 1280)
    }

    @Test func hd1080pWidth() {
        #expect(OutputResolution.hd1080p.width == 1080)
    }

    @Test func hd1080pHeight() {
        #expect(OutputResolution.hd1080p.height == 1920)
    }
}

// MARK: - BitratePreset Tests

@Suite("BitratePreset")
struct BitratePresetTests {

    @Test func lowBitrate() {
        #expect(BitratePreset.low.bitsPerSecond == 5_000_000)
    }

    @Test func mediumBitrate() {
        #expect(BitratePreset.medium.bitsPerSecond == 10_000_000)
    }

    @Test func highBitrate() {
        #expect(BitratePreset.high.bitsPerSecond == 15_000_000)
    }
}

// MARK: - VideoQualitySettings Tests
// .serialized: UserDefaults mutations must not interleave across parallel test runners

@Suite("VideoQualitySettings", .serialized)
struct VideoQualitySettingsTests {

    /// Clean slate before and after each test that touches UserDefaults.
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: VideoQualitySettings.defaultsKey)
    }

    @Test func defaultResolutionIs1080p() {
        let settings = VideoQualitySettings()
        #expect(settings.resolution == .hd1080p)
    }

    @Test func defaultBitrateIsHigh() {
        let settings = VideoQualitySettings()
        #expect(settings.bitrate == .high)
    }

    @Test func saveAndLoadRoundTrip() {
        cleanDefaults()
        defer { cleanDefaults() }

        var settings = VideoQualitySettings()
        settings.resolution = .hd720p
        settings.bitrate = .low

        let data = try! JSONEncoder().encode(settings)
        UserDefaults.standard.set(data, forKey: VideoQualitySettings.defaultsKey)

        let loaded = VideoQualitySettings.load()
        #expect(loaded.resolution == .hd720p)
        #expect(loaded.bitrate == .low)
    }

    @Test func loadWithNoStoredDataReturnsDefault() {
        cleanDefaults()
        defer { cleanDefaults() }

        let loaded = VideoQualitySettings.load()
        #expect(loaded.resolution == .hd1080p)
        #expect(loaded.bitrate == .high)
    }

    @Test func saveAndLoadViaConvenienceMethods() {
        cleanDefaults()
        defer { cleanDefaults() }

        var settings = VideoQualitySettings()
        settings.resolution = .hd720p
        settings.bitrate = .medium
        settings.save()

        let loaded = VideoQualitySettings.load()
        #expect(loaded.resolution == .hd720p)
        #expect(loaded.bitrate == .medium)
    }
}
