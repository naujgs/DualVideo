import Foundation

/// Output resolution options for the composited PiP recording.
/// Width/Height are in PORTRAIT orientation (output frame dimensions, not sensor dimensions).
/// The camera sensor delivers landscape; videoRotationAngle=90 corrects to portrait.
/// Width = short side (portrait), Height = long side (portrait).
enum OutputResolution: String, Codable, CaseIterable, Sendable {
    case hd720p  = "720p"
    case hd1080p = "1080p"

    /// Portrait width (short side).
    var width: Int {
        switch self {
        case .hd720p:  return 720
        case .hd1080p: return 1080
        }
    }

    /// Portrait height (long side).
    var height: Int {
        switch self {
        case .hd720p:  return 1280
        case .hd1080p: return 1920
        }
    }

    /// Landscape width used when selecting AVCaptureDevice.activeFormat.
    /// Camera sensor formats are expressed in landscape (width > height).
    /// For 720p  → filter dims.width == 1280
    /// For 1080p → filter dims.width == 1920
    var landscapeWidth: Int {
        switch self {
        case .hd720p:  return 1280
        case .hd1080p: return 1920
        }
    }
}

/// Frame rate options for the composited PiP recording.
/// Applied to both cameras via AVCaptureDevice frame duration settings.
enum FrameRatePreset: Int, CaseIterable, Codable, Sendable {
    case fps30  = 30
    case fps60  = 60
    case fps120 = 120

    var displayName: String {
        switch self {
        case .fps30:  return "30 FPS"
        case .fps60:  return "60 FPS"
        case .fps120: return "120 FPS"
        }
    }
}

/// User-configurable output quality settings. Shared instance lives on AppState.
/// Persisted via UserDefaults (individual keys per property).
/// D-01: default resolution = .hd1080p (matches existing hardcoded output)
/// D-02: default frameRate  = .fps30
struct VideoQualitySettings: Codable, Sendable {
    var resolution: OutputResolution = .hd1080p
    var frameRate: FrameRatePreset   = .fps30

    static let defaultsKey          = "com.naujgs.DualVideo.videoQualitySettings"
    static let frameRateDefaultsKey = "qualitySettings.frameRate"

    static func load() -> VideoQualitySettings {
        var settings = VideoQualitySettings()
        // Load resolution from legacy JSON blob if present
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(VideoQualitySettings.self, from: data) {
            settings = decoded
        }
        // Load frameRate from its own key (takes precedence over any value in legacy blob)
        if let rawValue = UserDefaults.standard.object(forKey: frameRateDefaultsKey) as? Int,
           let preset = FrameRatePreset(rawValue: rawValue) {
            settings.frameRate = preset
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: VideoQualitySettings.defaultsKey)
        UserDefaults.standard.set(frameRate.rawValue, forKey: VideoQualitySettings.frameRateDefaultsKey)
    }
}
