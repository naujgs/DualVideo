import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

/// Full-height sheet displayed after stopRecording when pendingTrimURL is non-nil.
/// State machine: idle → trimming → (success: dismiss) / (error: alert shown)
///
/// UI-SPEC:
/// - .presentationDetents([.large]) — full height required for video preview
/// - VideoPlayer fills top 60%
/// - TrimRangeBar below player with in/out labels
/// - "Save Trimmed" (primary) and "Save Full" (secondary) action buttons
struct TrimSheet: View {
    let sourceURL: URL
    let recordingManager: RecordingManager

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    @State private var inValue: Double = 0.0
    @State private var outValue: Double = 1.0
    @State private var trimPhase: TrimPhase = .idle
    @State private var showTrimFailedAlert = false
    @State private var showSaveFailedAlert = false  // pendingTrimURL unreachable

    private let trimManager = VideoTrimManager()

    enum TrimPhase {
        case idle
        case trimming
        case error(TrimError)
    }

    init(sourceURL: URL, recordingManager: RecordingManager) {
        self.sourceURL = sourceURL
        self.recordingManager = recordingManager
        self._player = State(initialValue: AVPlayer(url: sourceURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video preview — top 60% of sheet
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            // Trim controls — bottom 40%
            VStack(spacing: 16) {
                // Range bar
                TrimRangeBar(
                    inValue: $inValue,
                    outValue: $outValue,
                    duration: duration
                )
                .padding(.horizontal, 24)
                .onChange(of: inValue) { _, newVal in
                    player.seek(
                        to: CMTime(seconds: newVal * duration, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }

                // In/out time labels
                HStack {
                    Text(formatTime(inValue * duration))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(outValue * duration))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                // Action buttons
                HStack(spacing: 16) {
                    // Save Trimmed (primary)
                    Button {
                        saveTrimmed()
                    } label: {
                        if case .trimming = trimPhase {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Trimming\u{2026}")
                                    .font(.system(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Capsule())
                        } else {
                            Text("Save Trimmed")
                                .font(.system(.body))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }
                    .disabled({
                        if case .trimming = trimPhase { return true }
                        return false
                    }())

                    // Save Full (secondary)
                    Button("Save Full") {
                        saveFull()
                    }
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
                    .disabled({
                        if case .trimming = trimPhase { return true }
                        return false
                    }())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
        }
        .presentationDetents([.large])
        .task {
            await loadDuration()
        }
        .onDisappear {
            player.pause()
        }
        // Trim failed alert (export error)
        .alert("Trim Failed", isPresented: $showTrimFailedAlert) {
            Button("Save Full") { saveFull() }
            Button("Dismiss", role: .cancel) {
                if case .error = trimPhase { trimPhase = .idle }
            }
        } message: {
            Text("Could not trim recording. Try saving the full clip instead.")
        }
        // Save failed alert (file unreachable — T-04-04-03)
        .alert("Save Failed", isPresented: $showSaveFailedAlert) {
            Button("Dismiss", role: .cancel) {
                recordingManager.pendingTrimURL = nil
            }
        } message: {
            Text("Recording file unavailable. The clip may have been removed.")
        }
    }

    // MARK: - Actions

    private func saveTrimmed() {
        guard case .idle = trimPhase else { return }
        trimPhase = .trimming

        let inPoint  = CMTime(seconds: inValue * duration, preferredTimescale: 600)
        let outPoint = CMTime(seconds: outValue * duration, preferredTimescale: 600)
        let range    = CMTimeRange(start: inPoint, end: outPoint)

        Task { @MainActor in
            do {
                let trimmedURL = try await trimManager.trim(sourceURL: sourceURL, range: range)
                // Delete original temp file after successful trim to avoid orphaned files (T-04-04-01)
                try? FileManager.default.removeItem(at: sourceURL)
                recordingManager.saveRecording(url: trimmedURL)
                recordingManager.pendingTrimURL = nil
            } catch {
                trimPhase = .error(error as? TrimError ?? .exportFailed(error))
                showTrimFailedAlert = true
            }
        }
    }

    private func saveFull() {
        recordingManager.saveRecording(url: sourceURL)
        recordingManager.pendingTrimURL = nil
    }

    // MARK: - Helpers

    private func loadDuration() async {
        // Guard: check file exists before loading asset (T-04-04-03)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            showSaveFailedAlert = true
            return
        }
        let asset = AVURLAsset(url: sourceURL)
        if let d = try? await asset.load(.duration) {
            duration = d.seconds > 0 ? d.seconds : 0
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds))
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        // UI-SPEC: "0:03" format — m:ss, no leading zero on minutes
        return "\(m):\(String(format: "%02d", s))"
    }
}
