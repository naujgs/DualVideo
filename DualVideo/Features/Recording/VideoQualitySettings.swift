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

/// H.264 bitrate tiers for the composited PiP recording.
/// Values calibrated against native iPhone camera recordings (D-03, D-04, D-05, D-06).
enum BitratePreset: String, Codable, CaseIterable, Sendable {
    case low    = "Low"
    case medium = "Medium"
    case high   = "High"

    /// Video bitrate in bits per second.
    /// D-04: high   = 15 Mbps — matches front-camera native capture (front-camera.MOV ~15.4 Mbps)
    /// D-05: medium = 10 Mbps — matches existing hardcoded MovieRecorder value (proven on A12 XR)
    /// D-06: low    =  5 Mbps — half of medium; meaningful storage savings
    var bitsPerSecond: Int {
        switch self {
        case .low:    return  5_000_000  //  5 Mbps  ~37 MB/min
        case .medium: return 10_000_000  // 10 Mbps  ~75 MB/min
        case .high:   return 15_000_000  // 15 Mbps ~112 MB/min
        }
    }
}

/// User-configurable output quality settings. Shared instance lives on AppState.
/// Persisted via JSONEncoder/Codable to UserDefaults.
/// D-01: default resolution = .hd1080p (matches existing hardcoded output)
/// D-02: default bitrate    = .high    (matches existing hardcoded 10 Mbps — High is the tier name)
struct VideoQualitySettings: Codable, Sendable {
    var resolution: OutputResolution = .hd1080p
    var bitrate: BitratePreset       = .high

    static let defaultsKey = "com.naujgs.DualVideo.videoQualitySettings"

    static func load() -> VideoQualitySettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(VideoQualitySettings.self, from: data)
        else { return VideoQualitySettings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: VideoQualitySettings.defaultsKey)
    }
}
