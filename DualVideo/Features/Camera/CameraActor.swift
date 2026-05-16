import Foundation

/// Global actor isolating all AVFoundation session configuration work.
/// All CameraManager internal session mutations run on CameraActor.
/// This satisfies Swift 6 strict concurrency without sending AVFoundation objects across actor boundaries.
@globalActor
actor CameraActor: GlobalActor {
    static let shared = CameraActor()
}
