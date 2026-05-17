import AVFoundation
import Observation

enum AppRoute {
    case checkingCapability
    case unsupportedDevice
    case requestingPermissions
    case permissionsBlocked(which: String)
    case camera
}

@Observable
final class AppState {
    var route: AppRoute = .checkingCapability
    var deviceSupported: Bool = false
    var cameraManager: CameraManager = CameraManager()
    var recordingManager: RecordingManager = RecordingManager()

    init() {
        // Attach a PiPCompositor to CameraManager so it is ready before session starts
        cameraManager.compositor = PiPCompositor()
    }
}
