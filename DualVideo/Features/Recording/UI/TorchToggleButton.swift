import SwiftUI

/// Torch on/off toggle button. Tapping calls the provided action.
/// Shows a flashlight SF Symbol; filled when torch is on.
/// Glass circle background via cameraGlassBackground(in: Circle()) — applied at Button level
/// per RESEARCH.md Pitfall 3 to ensure correct tap area detection on iOS 26+.
struct TorchToggleButton: View {
    let isTorchOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(.title2, design: .default, weight: .medium))
                .foregroundStyle(isTorchOn ? Color.yellow : Color.white)
                .padding(16)
        }
        .cameraGlassBackground(in: Circle())
        .accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")
    }
}
