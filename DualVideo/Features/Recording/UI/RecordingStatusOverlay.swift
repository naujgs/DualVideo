import SwiftUI

/// Recording status indicator shown just above the Record button (D-03).
/// Shows a blinking red dot + elapsed time in MM:SS format.
/// No full-screen overlay or border — minimal indicator only (D-03).
/// Visible only during active recording; hidden when idle or finalizing.
struct RecordingStatusOverlay: View {
    let elapsedSeconds: Int
    @State private var dotVisible: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            // Blinking red dot
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(dotVisible ? 1.0 : 0.0)
                .onAppear {
                    // Blink animation: 0.6s on, 0.6s off
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        dotVisible = false
                    }
                }

            // Elapsed timer MM:SS
            Text(formattedTime)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording — \(formattedTime)")
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
