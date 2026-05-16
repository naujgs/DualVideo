import SwiftUI
import AVFoundation

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.route {
            case .checkingCapability:
                ProgressView("Starting…")
                    .task { await checkCapabilityAndPermissions() }

            case .unsupportedDevice:
                UnsupportedDeviceView()

            case .requestingPermissions:
                ProgressView("Requesting permissions…")

            case .permissionsBlocked(let which):
                PermissionsBlockedView(deniedPermission: which)

            case .camera:
                // Placeholder — replaced by Plan 02 CameraContentView
                Text("Camera ready")
                    .font(.largeTitle)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.route.id)
    }

    @MainActor
    private func checkCapabilityAndPermissions() async {
        // Capability gate (DEV-01) — per D-03/D-04
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            appState.route = .unsupportedDevice
            return
        }

        // Permission preflight (DEV-02) — per D-01/D-02
        appState.route = .requestingPermissions
        let manager = PermissionManager()
        let status = await manager.requestAll()

        switch status {
        case .granted:
            appState.route = .camera
        case .denied(let which):
            appState.route = .permissionsBlocked(which: which.rawValue)
        case .notDetermined:
            // Shouldn't reach here after requestAll(); show blocked as safe fallback
            appState.route = .permissionsBlocked(which: "unknown")
        }
    }
}

// MARK: - Permissions Blocked View (per D-02)
private struct PermissionsBlockedView: View {
    let deniedPermission: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Permission Required")
                .font(.title2.bold())
            Text(blockedMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var blockedMessage: String {
        switch deniedPermission {
        case "camera":
            return "DualVideo needs camera access to record video. Please enable Camera access in Settings."
        case "microphone":
            return "DualVideo needs microphone access to record audio. Please enable Microphone access in Settings."
        case "photos":
            return "DualVideo needs Photo Library access to save your recordings. Please enable Photos access in Settings."
        default:
            return "DualVideo needs camera, microphone, and Photo Library access to function. Please enable all permissions in Settings."
        }
    }
}

// MARK: - AppRoute Identifiable for animation
extension AppRoute: Equatable {
    var id: Int {
        switch self {
        case .checkingCapability: return 0
        case .unsupportedDevice: return 1
        case .requestingPermissions: return 2
        case .permissionsBlocked: return 3
        case .camera: return 4
        }
    }

    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        lhs.id == rhs.id
    }
}
