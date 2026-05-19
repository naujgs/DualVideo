import SwiftUI

/// Vertical zoom level indicator shown transiently on the left side during pinch-zoom.
/// Track runs bottom (1×) to top (3×). Yellow fill and white thumb show current position.
/// Caller controls visibility — animate in on zoom change, out after idle timeout.
struct ZoomIndicatorView: View {
    let zoomFactor: CGFloat

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0
    private let trackHeight: CGFloat = 140

    private var normalized: CGFloat {
        let t = (zoomFactor - minZoom) / (maxZoom - minZoom)
        return min(max(t, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.1f×", zoomFactor))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)

            ZStack(alignment: .bottom) {
                // Track background
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(width: 3, height: trackHeight)

                // Filled portion — yellow from bottom to current level
                Capsule()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 3, height: max(3, trackHeight * normalized))

                // Thumb at current position
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(y: -(trackHeight * normalized))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
