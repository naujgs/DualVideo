import AVFoundation
import SwiftUI
import UIKit

/// UIViewRepresentable that hosts an AVCaptureVideoPreviewLayer as a sublayer of a UIView.
/// This is the ONLY correct way to host AVCaptureVideoPreviewLayer in a SwiftUI view hierarchy.
/// Do NOT attempt to wrap AVCaptureVideoPreviewLayer in a SwiftUI Layer or Canvas — both have zero-copy hardware path loss.
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Assign preview layer into UIView's sublayer.
        // Called on main thread by SwiftUI — safe for CALayer operations.
        uiView.setPreviewLayer(previewLayer)
    }
}

/// UIView subclass that installs an AVCaptureVideoPreviewLayer as a sublayer
/// and keeps it frame-synced with the view's bounds via layoutSubviews.
final class PreviewUIView: UIView {
    private var installedLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        if installedLayer === layer { return }
        installedLayer?.removeFromSuperlayer()
        installedLayer = layer
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installedLayer?.frame = bounds
    }
}
