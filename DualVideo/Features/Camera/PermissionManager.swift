import AVFoundation
import Photos

enum PermissionDeniedReason: String, Sendable {
    case camera = "camera"
    case microphone = "microphone"
    case photos = "photos"
}

enum PermissionStatus: Sendable {
    case notDetermined
    case granted
    case denied(which: PermissionDeniedReason)
}

actor PermissionManager {
    func requestAll() async -> PermissionStatus {
        // Camera
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraGranted else { return .denied(which: .camera) }

        // Microphone
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else { return .denied(which: .microphone) }

        // Photos — requestAddOnlyAccess (iOS 14+, add-only per D-01)
        let photosStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard photosStatus == .authorized || photosStatus == .limited else {
            return .denied(which: .photos)
        }

        return .granted
    }

    func currentStatus() -> PermissionStatus {
        let cam = AVCaptureDevice.authorizationStatus(for: .video)
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if cam == .denied || cam == .restricted { return .denied(which: .camera) }
        if mic == .denied || mic == .restricted { return .denied(which: .microphone) }
        if photos == .denied || photos == .restricted { return .denied(which: .photos) }
        if cam == .authorized && mic == .authorized &&
           (photos == .authorized || photos == .limited) { return .granted }
        return .notDetermined
    }
}
