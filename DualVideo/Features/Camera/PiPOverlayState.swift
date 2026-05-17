import SwiftUI
import Observation

/// Observable state for the draggable front-camera PiP overlay.
/// Encapsulates drag offset tracking, safe-area clamp logic (D-07),
/// and corner snapping with cross-launch persistence (D-08, Phase 3).
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

    /// Finalize offset on drag end. Snaps to nearest corner with spring animation (D-08, Phase 3).
    ///
    /// Do NOT set offset/baseOffset here before calling snapToNearestCorner — doing so fires the
    /// view's implicit .animation(.interactiveSpring) modifier, which conflicts with the explicit
    /// withAnimation(.spring) inside snapToNearestCorner and produces a two-phase, jerky motion.
    /// updateDrag already clamps offset on every call, so self.offset is correct when this fires.
    func endDrag(translation: CGSize, containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) {
        snapToNearestCorner(containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
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

    // MARK: - Corner snapping (D-08, Phase 3)

    /// Corner index convention: 0=top-right (default), 1=top-left, 2=bottom-right, 3=bottom-left
    private static let cornerKey = "pip_corner_index"

    /// Snap PiP to the nearest corner using spring animation. Persists corner index to UserDefaults.
    /// Replaces the plain clamp behavior in endDrag (D-08).
    func snapToNearestCorner(containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) {
        let margin = Self.edgeMargin
        let xRight: CGFloat = 0
        let xLeft  = -(containerSize.width - pipSize.width - 2 * margin)
        let yTop:   CGFloat = 0
        let yBottom = containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom - pipSize.height - 2 * margin

        let corners: [(index: Int, offset: CGSize)] = [
            (0, CGSize(width: xRight, height: yTop)),
            (1, CGSize(width: xLeft,  height: yTop)),
            (2, CGSize(width: xRight, height: yBottom)),
            (3, CGSize(width: xLeft,  height: yBottom)),
        ]

        let nearest = corners.min { a, b in
            euclidean(offset, a.offset) < euclidean(offset, b.offset)
        }!

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            offset = nearest.offset
            baseOffset = nearest.offset
        }
        UserDefaults.standard.set(nearest.index, forKey: Self.cornerKey)
    }

    /// Restore PiP to the corner stored in UserDefaults. Call from onAppear with current geometry.
    func restorePersistedCorner(containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) {
        let index = UserDefaults.standard.integer(forKey: Self.cornerKey)
        let margin = Self.edgeMargin
        let xRight: CGFloat = 0
        let xLeft  = -(containerSize.width - pipSize.width - 2 * margin)
        let yTop:   CGFloat = 0
        let yBottom = containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom - pipSize.height - 2 * margin

        let targetOffset: CGSize
        switch index {
        case 1: targetOffset = CGSize(width: xLeft,  height: yTop)
        case 2: targetOffset = CGSize(width: xRight, height: yBottom)
        case 3: targetOffset = CGSize(width: xLeft,  height: yBottom)
        default: targetOffset = .zero  // index 0: top-right default
        }
        offset = targetOffset
        baseOffset = targetOffset
    }

    private func euclidean(_ a: CGSize, _ b: CGSize) -> CGFloat {
        let dx = a.width - b.width
        let dy = a.height - b.height
        return sqrt(dx * dx + dy * dy)
    }
}
