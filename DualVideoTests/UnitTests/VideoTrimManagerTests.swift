import Testing
import AVFoundation
import CoreMedia
import Foundation
@testable import DualVideo

@Suite("VideoTrimManager", .serialized)
struct VideoTrimManagerTests {

    // MARK: - Helpers

    /// Creates a silent AAC .mov with the specified duration using AVAssetWriter.
    /// Audio-only avoids AVAssetWriterInputPixelBufferAdaptor threading constraints in tests.
    /// Must run on @MainActor because AVAssetWriter requires it when called from a test host.
    @MainActor
    private func makeSilentMov(duration: Double) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-source-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(url: url, fileType: .mov)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100.0,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Build a silent PCM buffer for the full duration in one chunk.
        let sampleRate: CMTimeScale = 44100
        let totalSamples = Int(Double(sampleRate) * duration)
        let byteCount = totalSamples * 2  // 16-bit mono = 2 bytes/sample

        var formatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(allocator: nil,
                                       asbd: &asbd,
                                       layoutSize: 0,
                                       layout: nil,
                                       magicCookieSize: 0,
                                       magicCookie: nil,
                                       extensions: nil,
                                       formatDescriptionOut: &formatDesc)
        guard let formatDesc else { throw TrimError.exportFailed(nil) }

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0,
            blockBufferOut: &blockBuffer)
        guard let blockBuffer else { throw TrimError.exportFailed(nil) }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer,
                                   offsetIntoDestination: 0, dataLength: byteCount)

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: sampleRate),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: totalSamples,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer)
        if let sampleBuffer, audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }

        audioInput.markAsFinished()
        await writer.finishWriting()
        return url
    }

    // MARK: - Tests

    @Test func trimInvalidRangeThrows() async throws {
        let sourceURL = try await makeSilentMov(duration: 10)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let manager = VideoTrimManager()
        // inPoint >= outPoint — should throw .invalidRange
        let range = CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 600),
                                end:   CMTime(seconds: 3, preferredTimescale: 600))
        do {
            _ = try await manager.trim(sourceURL: sourceURL, range: range)
            Issue.record("Expected TrimError.invalidRange to be thrown")
        } catch TrimError.invalidRange {
            // Expected
        }
    }

    @Test func trimClampsInPointBelowZero() async throws {
        let sourceURL = try await makeSilentMov(duration: 5)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let manager = VideoTrimManager()
        // inPoint is negative — clamped to .zero
        let range = CMTimeRange(start: CMTime(seconds: -2, preferredTimescale: 600),
                                end:   CMTime(seconds: 3,  preferredTimescale: 600))
        let outputURL = try await manager.trim(sourceURL: sourceURL, range: range)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test func trimClampsOutPointBeyondDuration() async throws {
        let sourceURL = try await makeSilentMov(duration: 5)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let manager = VideoTrimManager()
        // outPoint beyond duration — clamped to asset.duration
        let range = CMTimeRange(start: CMTime(seconds: 1,  preferredTimescale: 600),
                                end:   CMTime(seconds: 99, preferredTimescale: 600))
        let outputURL = try await manager.trim(sourceURL: sourceURL, range: range)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test func successfulTrimProducesMovFile() async throws {
        let clipDuration = 10.0
        let sourceURL = try await makeSilentMov(duration: clipDuration)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let manager = VideoTrimManager()
        let desiredStart = 1.0
        let desiredEnd   = 4.0
        let range = CMTimeRange(start: CMTime(seconds: desiredStart, preferredTimescale: 600),
                                end:   CMTime(seconds: desiredEnd,   preferredTimescale: 600))

        let outputURL = try await manager.trim(sourceURL: sourceURL, range: range)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        #expect(outputURL.pathExtension == "mov")
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        // Verify output duration is approximately what was requested (within 1 second tolerance)
        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration = try await outputAsset.load(.duration)
        let expectedDuration = desiredEnd - desiredStart
        #expect(abs(outputDuration.seconds - expectedDuration) < 1.0)
    }
}
