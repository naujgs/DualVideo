import XCTest
import Photos
import Foundation
@testable import DualVideo

/// Unit tests for PhotoSaveManager (DEV-03, OUT-01, OUT-02).
/// Uses testable initializer injection to avoid real Photos/filesystem side effects.
///
/// Note: completion closures are @Sendable (Swift 6 requirement). Tests use
/// nonisolated(unsafe) var for result capture since XCTestExpectation already
/// serialises access: fulfill() happens-before wait() returns.
@MainActor
final class PhotoSaveManagerTests: XCTestCase {

    // MARK: - Test 1: Permission denied → .failure(.permissionDenied)

    func testSaveFailsWhenPermissionDenied() {
        let saver = PhotoSaveManager(
            statusProvider: { .denied },
            performChanges: { _, _ in
                XCTFail("performChanges must not be called when permission is denied")
            }
        )

        let expectation = expectation(description: "completion called")
        // nonisolated(unsafe): safe because XCTestExpectation serialises access
        // (fulfill() happens-before wait() returns, so we read after all writes).
        nonisolated(unsafe) var result: Result<Void, PhotoSaveError>?

        saver.saveVideoToPhotos(url: URL(string: "file:///tmp/test.mov")!) { res in
            result = res
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        if case .failure(let err) = result {
            XCTAssertEqual(err, .permissionDenied)
        } else {
            XCTFail("Expected .failure(.permissionDenied), got \(String(describing: result))")
        }
    }

    // MARK: - Test 2: Temp file deleted on success

    func testTempFileDeletedOnSuccess() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo_save_test_\(UUID().uuidString).mov")

        // Create a real temp file
        try "fake mov data".write(to: tempURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Temp file must exist before save")

        let saver = PhotoSaveManager(
            statusProvider: { .authorized },
            performChanges: { _, completionHandler in
                // Mock: simulate successful Photos save
                completionHandler(true, nil)
            }
        )

        let expectation = expectation(description: "completion called")
        nonisolated(unsafe) var result: Result<Void, PhotoSaveError>?

        saver.saveVideoToPhotos(url: tempURL) { res in
            result = res
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempURL.path),
            "Temp file must be deleted after successful save"
        )
        if case .success = result { } else {
            XCTFail("Expected .success, got \(String(describing: result))")
        }
    }

    // MARK: - Test 3: Temp file preserved on failure

    func testTempFilePreservedOnFailure() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo_save_test_\(UUID().uuidString).mov")

        // Create a real temp file
        try "fake mov data".write(to: tempURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Temp file must exist before save")

        let saver = PhotoSaveManager(
            statusProvider: { .authorized },
            performChanges: { _, completionHandler in
                // Mock: simulate failed Photos save
                completionHandler(false, nil)
            }
        )

        let expectation = expectation(description: "completion called")
        nonisolated(unsafe) var result: Result<Void, PhotoSaveError>?

        saver.saveVideoToPhotos(url: tempURL) { res in
            result = res
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: tempURL.path),
            "Temp file must be preserved after failed save"
        )
        if case .failure = result { } else {
            XCTFail("Expected .failure, got \(String(describing: result))")
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Test 4: Completion dispatches to main thread

    func testSaveResultPublishedOnMainThread() async {
        let saver = PhotoSaveManager(
            statusProvider: { .authorized },
            performChanges: { _, completionHandler in
                // Call from a background queue to simulate real Photos behavior
                DispatchQueue.global(qos: .background).async {
                    completionHandler(true, nil)
                }
            }
        )

        // Create a temp file so removeItem doesn't error
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("main_thread_test_\(UUID().uuidString).mov")
        try? "fake".write(to: tempURL, atomically: true, encoding: .utf8)

        // Use async/await via withCheckedContinuation so the test coroutine suspends
        // and the runloop can deliver the DispatchQueue.main.async from PhotoSaveManager.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            saver.saveVideoToPhotos(url: tempURL) { _ in
                XCTAssertTrue(Thread.isMainThread, "Completion must be called on the main thread")
                continuation.resume()
            }
        }
    }
}
