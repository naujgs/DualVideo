import SwiftUI

/// Horizontal row of three tappable zoom preset buttons: 1x, 2x, 3x.
///
/// Replaces ZoomLabelView. Matches the iPhone Camera app aesthetic:
/// capsule-shaped glass buttons, active state expressed through bold weight + yellow color.
///
/// Active threshold: abs(currentZoom - preset) < 0.25 (D-07, Claude's discretion).
/// The threshold covers normal tap-settle positions without requiring exact floating-point equality.
///
/// IMPORTANT: The caller MUST pass `activeZoomBase` as an @Binding so tapping a preset
/// updates the baseline. Without this, the next pinch gesture will snap back to the wrong zoom.
struct ZoomPresetView: View {
    let currentZoom: CGFloat
    let onPresetSelected: (CGFloat) -> Void

    private let presets: [CGFloat] = [1.0, 2.0, 3.0]

    private func isActive(_ preset: CGFloat) -> Bool {
        abs(currentZoom - preset) < 0.25
    }

    private func presetLabel(_ factor: CGFloat) -> String {
        // Presets are whole numbers (1, 2, 3) — display as "1x", "2x", "3x"
        "\(Int(factor))x"
    }

    var body: some View {
        let buttonRow = HStack(spacing: 8) {
            ForEach(presets, id: \.self) { preset in
                Button(action: { onPresetSelected(preset) }) {
                    Text(presetLabel(preset))
                        .font(.system(size: 15, weight: isActive(preset) ? .bold : .regular,
                                      design: .monospaced))
                        .foregroundStyle(isActive(preset) ? Color.yellow : Color.white)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .cameraGlassBackground(in: Circle())
                .accessibilityLabel(
                    isActive(preset)
                        ? "\(Int(preset))x zoom, selected"
                        : "\(Int(preset))x zoom"
                )
                .accessibilityAddTraits(isActive(preset) ? .isSelected : [] as AccessibilityTraits)
            }
        }

        if #available(iOS 26, *) {
            // GlassEffectContainer groups adjacent glass capsules for merged-pill rendering.
            // The spacing: 8 value targets the merged appearance; tune on device if needed (A2).
            GlassEffectContainer(spacing: 8) {
                buttonRow
            }
        } else {
            buttonRow
        }
    }
}
