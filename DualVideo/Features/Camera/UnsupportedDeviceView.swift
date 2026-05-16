import SwiftUI

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Dual-Camera Recording Unavailable")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(
                "DualVideo requires an iPhone with an A12 Bionic chip or newer (iPhone XR, XS, or later) to record from both cameras simultaneously.\n\nThis device does not support dual-camera recording."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding()
    }
}
