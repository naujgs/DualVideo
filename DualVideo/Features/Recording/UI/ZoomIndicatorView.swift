import SwiftUI

/// Vertical zoom indicator — displays current zoom level and responds to drag gestures.
/// Drag up to zoom in, drag down to zoom out. Full bar height = full 1×–3× range.
/// Caller is responsible for show/hide; use onDragStarted/onDragEnded to suppress auto-hide.
struct ZoomIndicatorView: View {
    let zoomFactor: CGFloat
    let onZoomChanged: (CGFloat) -> Void
    var onDragStarted: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0
    private let trackHeight: CGFloat = 140

    /// Zoom captured at the start of a drag — held until gesture ends.
    @State private var dragStartZoom: CGFloat? = nil

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

                // Yellow fill from bottom to current zoom level
                Capsule()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 3, height: max(3, trackHeight * normalized))

                // Thumb at current position
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(y: -(trackHeight * normalized))
            }
            // Widen hit area so the thin track is easy to grab
            .frame(width: 44, height: trackHeight)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if dragStartZoom == nil {
                        dragStartZoom = zoomFactor
                        onDragStarted?()
                    }
                    // Upward drag (negative height) zooms in; downward zooms out.
                    // Full trackHeight pixels covers the full minZoom–maxZoom range.
                    let sensitivity = trackHeight / (maxZoom - minZoom)
                    let delta = -value.translation.height / sensitivity
                    let newZoom = min(max((dragStartZoom ?? zoomFactor) + delta, minZoom), maxZoom)
                    onZoomChanged(newZoom)
                }
                .onEnded { _ in
                    dragStartZoom = nil
                    onDragEnded?()
                }
        )
    }
}
