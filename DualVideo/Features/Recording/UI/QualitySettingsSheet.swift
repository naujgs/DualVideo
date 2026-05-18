import SwiftUI

/// Bottom sheet for resolution and bitrate selection.
/// Displayed from CameraContentView via .sheet(isPresented: $showQualitySettings).
/// Settings are persisted to UserDefaults on sheet dismissal (onDisappear).
///
/// UI-SPEC: presentationDetents([.height(240)]), VStack(spacing: 24), footnote section headers,
/// segmented Picker, caption file size hint.
struct QualitySettingsSheet: View {
    @Binding var settings: VideoQualitySettings
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Resolution picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Resolution", selection: $settings.resolution) {
                    ForEach(OutputResolution.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Quality (bitrate) picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Quality")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Quality", selection: $settings.bitrate) {
                    ForEach(BitratePreset.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.segmented)
            }

            // File size hint (D-07: correct values per CONTEXT.md decisions)
            // NOTE: File size is driven by bitrate — not resolution — per D-07.
            // Low=~37 MB/min, Medium=~75 MB/min, High=~112 MB/min.
            Text(fileSizeHint)
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .onDisappear {
            onDismiss()
        }
    }

    /// Returns the file size hint string for the current bitrate selection.
    /// D-07: Low=~37 MB/min, Medium=~75 MB/min, High=~112 MB/min.
    /// These values supersede the UI-SPEC copywriting contract (which had stale values ~22/45/75).
    /// D-07 is the authoritative decision from CONTEXT.md.
    private var fileSizeHint: String {
        switch settings.bitrate {
        case .low:    return "~37 MB/min"
        case .medium: return "~75 MB/min"
        case .high:   return "~112 MB/min"
        }
    }
}
