import SwiftUI

extension View {
    /// Applies a glass/material background appropriate for the current iOS version.
    ///
    /// - iOS 26+: uses `.glassEffect(.regular, in: shape)` (Liquid Glass)
    /// - iOS 18–25: uses `.background(.ultraThinMaterial, in: shape)`
    ///
    /// Usage: `.cameraGlassBackground(in: Circle())` or `.cameraGlassBackground(in: Capsule())`
    ///
    /// IMPORTANT: Apply at the Button or outermost container level — not nested inside
    /// a label's child view. Applying inside a label causes invisible tap areas on iOS 26.
    /// Never stack this modifier inside another view that already has glassEffect applied.
    @ViewBuilder
    func cameraGlassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
