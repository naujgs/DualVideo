import SwiftUI

struct ZoomLabelView: View {
    let zoomFactor: CGFloat

    var body: some View {
        Text(Self.formatZoom(zoomFactor))
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.4))
            .clipShape(Capsule())
    }

    /// Public for testability — pure function, no view dependencies.
    /// Rounds to one decimal place using standard rounding (half-up) before formatting,
    /// avoiding IEEE 754 truncation artifacts (e.g. 1.45 → "1.5x" not "1.4x").
    static func formatZoom(_ factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        return String(format: "%.1fx", rounded)
    }
}
