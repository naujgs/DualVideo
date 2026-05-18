import SwiftUI

/// Two-thumb range slider for trim in/out point selection.
/// UI-SPEC: track height 4pt, white.opacity(0.3) background, white selected range,
/// 24pt circle thumbs with .black.opacity(0.4) shadow radius 4, minimum 1.0s gap.
struct TrimRangeBar: View {
    @Binding var inValue: Double   // fractional [0.0, 1.0]
    @Binding var outValue: Double  // fractional [0.0, 1.0]
    let duration: Double           // total clip duration in seconds (for accessibility labels)

    /// Minimum trim duration: 1.0 second expressed as fraction of total duration.
    /// Guard: if duration is 0 or very short, fall back to a 0.01 minimum to prevent
    /// division by zero or inverted range.
    private var minimumGap: Double {
        guard duration > 0 else { return 0.01 }
        return max(1.0 / duration, 0.01)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)

                // Selected range highlight
                let trackWidth = geo.size.width
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, (outValue - inValue) * trackWidth), height: 4)
                    .offset(x: inValue * trackWidth)
            }

            // In-point (start) slider — underneath out-point slider in z-order
            // The invisible Slider approach (opacity 0.01) is a known SwiftUI pattern for
            // custom-drawn sliders. Track+range is drawn in the ZStack above; Sliders provide
            // gesture handling and accessibility. In-point has lower z-order so out-point
            // slider wins for taps near the right end (RESEARCH.md A7).
            Slider(value: $inValue, in: 0.0...(outValue - minimumGap))
                .opacity(0.01)  // invisible but interactive — track rendered above
                .frame(height: 44)  // 44pt touch target per HIG
                .accessibilityLabel("Trim start")
                .accessibilityValue(formatTime(inValue * duration))

            // Out-point (end) slider — on top in z-order
            Slider(value: $outValue, in: (inValue + minimumGap)...1.0)
                .opacity(0.01)  // invisible but interactive
                .frame(height: 44)
                .accessibilityLabel("Trim end")
                .accessibilityValue(formatTime(outValue * duration))
        }
        .frame(height: 44)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        // UI-SPEC: "0:03" format — m:ss, no leading zero on minutes
        return "\(m):\(String(format: "%02d", s))"
    }
}
