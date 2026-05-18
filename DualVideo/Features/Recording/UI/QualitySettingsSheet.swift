import SwiftUI

/// Bottom sheet for resolution and frame rate selection.
/// Displayed from CameraContentView via .sheet(isPresented: $showQualitySettings).
/// Settings are persisted to UserDefaults on sheet dismissal (onDisappear).
///
/// UI-SPEC: presentationDetents([.height(260)]), VStack(spacing: 24), footnote section headers,
/// segmented Picker, caption subtitle "Applies to both cameras".
struct QualitySettingsSheet: View {
    @Binding var settings: VideoQualitySettings
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Sheet title + subtitle
            VStack(spacing: 4) {
                Text("Video Quality")
                    .font(.system(.headline))
                Text("Applies to both cameras")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

            // Frame rate picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Frame Rate")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Frame Rate", selection: $settings.frameRate) {
                    ForEach(FrameRatePreset.allCases, id: \.self) { fps in
                        Text(fps.displayName).tag(fps)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .onDisappear {
            onDismiss()
        }
    }
}
