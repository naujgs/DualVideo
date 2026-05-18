import AVFoundation
import CoreMedia
import Foundation
import os.log

private let logger = Logger(subsystem: "com.naujgs.DualVideo", category: "VideoTrimManager")

enum TrimError: Error, LocalizedError {
    case invalidRange
    case sessionUnavailable
    case exportFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .invalidRange:        return "Trim range is invalid (inPoint must be less than outPoint)"
        case .sessionUnavailable:  return "Could not create AVAssetExportSession"
        case .exportFailed(let e): return "Export failed: \(e?.localizedDescription ?? "unknown")"
        }
    }
}

/// Trims a composited .mov file using AVAssetExportSession (passthrough — no re-encode).
/// All methods are async and safe to call from any actor.
actor VideoTrimManager {

    /// Trim sourceURL to the given CMTimeRange and return the URL of the trimmed output.
    /// - Parameters:
    ///   - sourceURL: URL of the composited .mov produced by MovieRecorder.
    ///   - range: Desired trim range. Clamped to [.zero, asset.duration].
    /// - Returns: URL of the trimmed .mov in the system temp directory.
    /// - Throws: TrimError if range is invalid or export fails.
    ///
    /// Security: inPoint and outPoint are clamped before passing to AVAssetExportSession.
    /// This prevents out-of-bounds CMTimeRange inputs from causing undefined export behavior (ASVS V5).
    func trim(sourceURL: URL, range: CMTimeRange) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // Load duration so we can clamp — AVURLAsset.load(.duration) is async on iOS 16+
        let assetDuration: CMTime
        do {
            assetDuration = try await asset.load(.duration)
        } catch {
            throw TrimError.exportFailed(error)
        }

        // SECURITY: Clamp range to valid asset bounds (ASVS V5 — input validation)
        let clampedStart = CMTimeMaximum(.zero, range.start)
        let clampedEnd   = CMTimeMinimum(assetDuration, range.end)
        guard CMTimeCompare(clampedStart, clampedEnd) < 0 else {
            throw TrimError.invalidRange
        }
        let clampedRange = CMTimeRange(start: clampedStart, end: clampedEnd)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else { throw TrimError.sessionUnavailable }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        session.outputURL      = outputURL
        session.outputFileType = .mov
        session.timeRange      = clampedRange

        await session.export()

        guard session.status == .completed else {
            // SECURITY: Clean up partial output on failure to avoid orphaned temp files
            try? FileManager.default.removeItem(at: outputURL)
            throw TrimError.exportFailed(session.error)
        }

        logger.info("VideoTrimManager: trim complete, output=\(outputURL.lastPathComponent), duration=\(clampedRange.duration.seconds, format: .fixed(precision: 2))s")
        return outputURL
    }
}
