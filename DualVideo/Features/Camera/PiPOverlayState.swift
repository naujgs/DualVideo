import SwiftUI
import Observation

/// Observable state for the draggable front-camera PiP overlay.
/// Encapsulates drag offset tracking and safe-area clamp logic (D-07).
/// Does NOT implement corner snapping — that is deferred to Phase 3 (D-08).
@Observable
final class PiPOverlayState {
    /// Current applied position offset from the default top-right anchor (D-05).
    /// CGSize(0, 0) = top-right default position.
    var offset: CGSize = .zero

    /// Accumulated offset from previous drags (before current drag started).
    var baseOffset: CGSize = .zero

    /// Inset margin applied on all edges (D-07: safe-area inset margins).
    static let edgeMargin: CGFloat = 12.0

    /// Update offset during a drag gesture, with real-time clamping.
    /// - Parameters:
    ///   - translation: Current drag translation from gesture.
    ///   - containerSize: Full size of the container view (CGSize).
    ///   - pipSize: Size of the PiP overlay view.
    ///   - safeAreaInsets: EdgeInsets of the safe area.
    func updateDrag(translation: CGSize, containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) {
        let proposed = CGSize(
            width: baseOffset.width + translation.width,
            height: baseOffset.height + translation.height
        )
        offset = clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
    }

    /// Finalize offset on drag end. Clamps and saves as new base.
    func endDrag(translation: CGSize, containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) {
        let proposed = CGSize(
            width: baseOffset.width + translation.width,
            height: baseOffset.height + translation.height
        )
        let clamped = clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        offset = clamped
        baseOffset = clamped
        // NOTE: no corner snapping — D-08 deferred to Phase 3
    }

    /// Pure function: compute safe-area-clamped offset from a proposed offset.
    /// This is the unit-testable core — extracted to be tested without SwiftUI.
    func clampedOffset(proposed: CGSize, containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) -> CGSize {
        let margin = Self.edgeMargin

        // Default anchor is top-right; offset moves PiP from that anchor.
        // Compute the absolute top-right origin the PiP would be at with zero offset:
        //   x_anchor = containerSize.width - pipSize.width - margin
        //   y_anchor = safeAreaInsets.top + margin
        //
        // With offset applied:
        //   x_abs = x_anchor + proposed.width  (positive offset moves right, negative moves left)
        //   y_abs = y_anchor + proposed.height  (positive offset moves down, negative moves up)
        //
        // Clamp x_abs to [margin, containerSize.width - pipSize.width - margin]
        // Clamp y_abs to [safeAreaInsets.top + margin, containerSize.height - safeAreaInsets.bottom - pipSize.height - margin]

        let xAnchor = containerSize.width - pipSize.width - margin
        let yAnchor = safeAreaInsets.top + margin

        var xAbs = xAnchor + proposed.width
        var yAbs = yAnchor + proposed.height

        // Horizontal clamp
        let xMin = margin
        let xMax = containerSize.width - pipSize.width - margin
        xAbs = min(max(xAbs, xMin), xMax)

        // Vertical clamp
        let yMin = safeAreaInsets.top + margin
        let yMax = containerSize.height - safeAreaInsets.bottom - pipSize.height - margin
        yAbs = min(max(yAbs, yMin), yMax)

        // Convert back to offset from anchor
        let clampedOffsetX = xAbs - xAnchor
        let clampedOffsetY = yAbs - yAnchor

        return CGSize(width: clampedOffsetX, height: clampedOffsetY)
    }
}
