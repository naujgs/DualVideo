import SwiftUI

/// Torch on/off toggle button. Tapping calls the provided action.
/// Shows a flashlight SF Symbol; filled when torch is on.
struct TorchToggleButton: View {
    let isTorchOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isTorchOn ? Color.yellow : Color.white)
                .padding(16)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")
    }
}
