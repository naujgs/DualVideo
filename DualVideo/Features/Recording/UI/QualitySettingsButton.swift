import SwiftUI

/// Entry point for quality settings on the main camera UI.
/// Matches TorchToggleButton style: Circle, .black.opacity(0.4), .white foreground, 44pt touch target.
/// Disabled (opacity 0.5) while recording is active — resolution cannot change mid-recording.
struct QualitySettingsButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            guard !isRecording else { return }
            onTap()
        }) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.5 : 1.0)
        .accessibilityLabel(isRecording ? "Video quality settings, unavailable" : "Video quality settings")
    }
}
