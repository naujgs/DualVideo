import Photos
import Foundation
import os.log

private let logger = Logger(subsystem: "com.naujgs.DualVideo", category: "PhotoSaveManager")

/// Errors that can occur when saving to Photos.
enum PhotoSaveError: Error, Equatable {
    case permissionDenied
    case saveFailed(String)  // error.localizedDescription; Equatable-safe string
}

/// Saves a video file to the Photos Camera Roll via PHPhotoLibrary.
/// Deletes the temp file only on confirmed save success.
/// All completion callbacks are dispatched to the main thread.
///
/// Injectable dependencies (statusProvider, performChanges) allow full unit testing
/// without real Photos access or filesystem side effects.
final class PhotoSaveManager {

    // MARK: - Testable injection points

    /// Returns current Photos authorization status. Defaults to real PHPhotoLibrary status.
    private let statusProvider: () -> PHAuthorizationStatus
    /// Executes the Photos save operation. Defaults to real PHPhotoLibrary.shared().performChanges.
    private let performChanges: (@escaping () -> Void, @escaping (Bool, Error?) -> Void) -> Void

    // MARK: - Init

    init(
        statusProvider: @escaping () -> PHAuthorizationStatus = {
            PHPhotoLibrary.authorizationStatus(for: .addOnly)
        },
        performChanges: @escaping (@escaping () -> Void, @escaping (Bool, Error?) -> Void) -> Void = {
            PHPhotoLibrary.shared().performChanges($0, completionHandler: $1)
        }
    ) {
        self.statusProvider = statusProvider
        self.performChanges = performChanges
    }

    // MARK: - Public API

    /// Save video file at url to Photos Camera Roll. Deletes temp file only on success.
    /// Completion is always called on the MAIN thread (T-03-01-03 mitigation).
    ///
    /// - Parameters:
    ///   - url: File URL of the .mov to save.
    ///   - completion: Result<Void, PhotoSaveError> called on main queue.
    func saveVideoToPhotos(url: URL, completion: @escaping @Sendable (Result<Void, PhotoSaveError>) -> Void) {
        // DEV-03: re-check authorization status at save time (user may have revoked in Settings)
        // T-03-01-01: elevation of privilege mitigation — always guard before performChanges
        let status = statusProvider()
        guard status == .authorized || status == .limited else {
            DispatchQueue.main.async { completion(.failure(.permissionDenied)) }
            return
        }

        // OUT-01: save via PhotoKit — the only approved API for .addOnly permission
        performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, { success, error in
            // T-03-01-03: always dispatch to main before updating @Observable state
            DispatchQueue.main.async {
                if success {
                    // OUT-01: temp file deleted ONLY after confirmed Photos save (avoids data loss)
                    try? FileManager.default.removeItem(at: url)
                    logger.info("PhotoSaveManager: saved and cleaned up \(url.lastPathComponent)")
                    completion(.success(()))
                } else {
                    let msg = error?.localizedDescription ?? "unknown"
                    logger.error("PhotoSaveManager: save failed — \(msg)")
                    completion(.failure(.saveFailed(msg)))
                }
            }
        })
    }
}
