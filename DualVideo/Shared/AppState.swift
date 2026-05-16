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
}
