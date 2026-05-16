import SwiftUI
import AVFoundation

/// Root camera view: back camera full-bleed (D-06) behind front-camera PiP placeholder.
/// Plan 03 adds the drag gesture and pinch-to-zoom interaction layer on top.
struct CameraContentView: View {
    let cameraManager: CameraManager

    var body: some View {
        ZStack {
            // Back camera: full-bleed (D-06)
            CameraPreviewView(previewLayer: cameraManager.backPreviewLayer)
                .ignoresSafeArea()

            // Front camera PiP: placeholder position — Plan 03 adds drag gesture
            // Default: top-right, 28% of screen width, safe-area inset (D-05)
            GeometryReader { geo in
                let pipWidth = geo.size.width * 0.28
                let pipHeight = pipWidth * (4.0 / 3.0)  // front camera aspect ratio

                CameraPreviewView(previewLayer: cameraManager.frontPreviewLayer)
                    .frame(width: pipWidth, height: pipHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, geo.safeAreaInsets.top + 12)
                    .padding(.trailing, 12)
            }
        }
        .background(Color.black)
    }
}
