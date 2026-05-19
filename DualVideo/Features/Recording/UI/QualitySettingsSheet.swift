import SwiftUI

/// Bottom sheet for resolution and frame rate selection.
/// Displayed from CameraContentView via .sheet(isPresented: $showQualitySettings).
/// Settings are persisted to UserDefaults on sheet dismissal (onDisappear).
///
/// UI-SPEC: presentationDetents([.height(320)]), VStack(spacing: 24), footnote section headers,
/// segmented Picker, caption subtitle "Applies to both cameras".
/// K4-02: supports4K parameter controls 4K visibility (hide, not disable — Apple HIG).
/// K4-05: storageEstimate computed property shows recording time remaining.
struct QualitySettingsSheet: View {
    @Binding var settings: VideoQualitySettings
    let supports4K: Bool          // K4-02: passed from CameraContentView; hides .uhd4K when false
    let onDismiss: () -> Void

    @State private var freeBytes: Int64 = 0   // K4-05: loaded once in .onAppear

    var body: some View {
        VStack(spacing: 24) {
            // Sheet title + subtitle (UNCHANGED from prior implementation)
            VStack(spacing: 4) {
                Text("Video Quality")
                    .font(.system(.headline))
                Text("Applies to both cameras")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Resolution picker — K4-02: filter .uhd4K when supports4K == false
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Resolution", selection: $settings.resolution) {
                    ForEach(
                        OutputResolution.allCases.filter { $0 != .uhd4K || supports4K },
                        id: \.self
                    ) { r in
                        Text(verbatim: r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)

                // K4-05: Storage estimate label — visible once freeBytes is loaded
                if freeBytes > 0 {
                    Text(storageEstimate)
                        .font(.system(.caption2))
                        .foregroundStyle(freeBytes < 1_000_000_000 ? .orange : .secondary)
                }
            }

            // Frame rate picker (UNCHANGED)
            VStack(alignment: .leading, spacing: 8) {
                Text("Frame Rate")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Frame Rate", selection: $settings.frameRate) {
                    ForEach(FrameRatePreset.allCases, id: \.self) { fps in
                        Text(verbatim: fps.displayName).tag(fps)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .presentationDetents([.height(320)])   // K4-02/K4-05: increased from 260 (RESEARCH.md Pitfall 4)
        .presentationDragIndicator(.visible)
        .onAppear {
            // K4-05: query free storage once when sheet appears.
            // volumeAvailableCapacityForImportantUsage is Apple's recommended API for
            // user-data writes — accounts for OS reserves. (RESEARCH.md Pattern 4)
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        }
        .onDisappear {
            onDismiss()
        }
    }

    // K4-05: Computed property — re-evaluates whenever settings.resolution changes
    // (SwiftUI re-renders body on @Binding change, which re-evaluates this property).
    // Bitrate constants: 720p=8Mbps H.264, 1080p=16Mbps H.264, 4K=45Mbps HEVC.
    // (RESEARCH.md Pattern 4 — exact code from instructions)
    private var storageEstimate: String {
        let bitrateBytesPerSec: Int64
        switch settings.resolution {
        case .hd720p:  bitrateBytesPerSec = 8_000_000 / 8
        case .hd1080p: bitrateBytesPerSec = 16_000_000 / 8
        case .uhd4K:   bitrateBytesPerSec = 45_000_000 / 8
        }
        guard bitrateBytesPerSec > 0, freeBytes > 0 else {
            return String(localized: "Storage unavailable",
                          comment: "Shown when free storage cannot be determined")
        }
        if freeBytes < 1_000_000_000 {
            return String(localized: "Low storage",
                          comment: "Shown when device has less than 1 GB free storage")
        }
        let seconds = Int(freeBytes / bitrateBytesPerSec)
        let minutes = seconds / 60
        if minutes == 0 {
            return String(localized: "<1 min remaining",
                          comment: "Shown when less than one minute of recording time remains")
        }
        if minutes < 60 {
            let count = Int64(minutes)
            return String(localized: "~\(count, specifier: "%lld") min remaining",
                          comment: "Approximate minutes of recording time remaining; count is the number of minutes")
        }
        let hours = Int64(minutes / 60)
        return String(localized: "~\(hours, specifier: "%lld") hr remaining",
                      comment: "Approximate hours of recording time remaining; count is the number of hours")
    }
}
