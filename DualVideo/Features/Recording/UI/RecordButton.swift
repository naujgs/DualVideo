import SwiftUI

/// Bottom-center Record/Stop button (D-02).
/// Large circular red button above the home indicator, thumb-reachable.
/// Shows red circle when idle (tap to record), white square when recording (tap to stop).
/// No countdown — tap starts/stops immediately (D-04).
struct RecordButton: View {
    let isRecording: Bool
    let isFinalizing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer ring — always visible
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)

                // Inner shape: red circle (idle) or white rounded square (recording)
                if isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 58, height: 58)
                }
            }
        }
        .disabled(isFinalizing)
        .opacity(isFinalizing ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")
    }
}
