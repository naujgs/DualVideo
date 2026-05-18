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

// MARK: - FrameRatePreset Tests

@Suite("FrameRatePreset")
struct FrameRatePresetTests {

    @Test func fps30RawValue() {
        #expect(FrameRatePreset.fps30.rawValue == 30)
    }

    @Test func fps60RawValue() {
        #expect(FrameRatePreset.fps60.rawValue == 60)
    }

    @Test func fps120RawValue() {
        #expect(FrameRatePreset.fps120.rawValue == 120)
    }

    @Test func fps30DisplayName() {
        #expect(FrameRatePreset.fps30.displayName == "30 FPS")
    }

    @Test func fps60DisplayName() {
        #expect(FrameRatePreset.fps60.displayName == "60 FPS")
    }

    @Test func fps120DisplayName() {
        #expect(FrameRatePreset.fps120.displayName == "120 FPS")
    }
}

// MARK: - VideoQualitySettings Tests
// .serialized: UserDefaults mutations must not interleave across parallel test runners

@Suite("VideoQualitySettings", .serialized)
struct VideoQualitySettingsTests {

    /// Clean slate before and after each test that touches UserDefaults.
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: VideoQualitySettings.defaultsKey)
        UserDefaults.standard.removeObject(forKey: VideoQualitySettings.frameRateDefaultsKey)
    }

    @Test func defaultResolutionIs1080p() {
        let settings = VideoQualitySettings()
        #expect(settings.resolution == .hd1080p)
    }

    @Test func defaultFrameRateIs30fps() {
        let settings = VideoQualitySettings()
        #expect(settings.frameRate == .fps30)
    }

    @Test func saveAndLoadRoundTrip() {
        cleanDefaults()
        defer { cleanDefaults() }

        var settings = VideoQualitySettings()
        settings.resolution = .hd720p
        settings.frameRate = .fps60
        settings.save()

        let loaded = VideoQualitySettings.load()
        #expect(loaded.resolution == .hd720p)
        #expect(loaded.frameRate == .fps60)
    }

    @Test func loadWithNoStoredDataReturnsDefault() {
        cleanDefaults()
        defer { cleanDefaults() }

        let loaded = VideoQualitySettings.load()
        #expect(loaded.resolution == .hd1080p)
        #expect(loaded.frameRate == .fps30)
    }

    @Test func saveAndLoadViaConvenienceMethods() {
        cleanDefaults()
        defer { cleanDefaults() }

        var settings = VideoQualitySettings()
        settings.resolution = .hd720p
        settings.frameRate = .fps120
        settings.save()

        let loaded = VideoQualitySettings.load()
        #expect(loaded.resolution == .hd720p)
        #expect(loaded.frameRate == .fps120)
    }

    @Test func frameRatePersistedWithOwnKey() {
        cleanDefaults()
        defer { cleanDefaults() }

        var settings = VideoQualitySettings()
        settings.frameRate = .fps60
        settings.save()

        // Verify the dedicated key was written
        let rawValue = UserDefaults.standard.integer(forKey: VideoQualitySettings.frameRateDefaultsKey)
        #expect(rawValue == 60)
    }
}
