import SwiftUI
import AVFoundation

struct CameraContentView: View {
    let cameraManager: CameraManager

    @State private var pipState = PiPOverlayState()
    @State private var activeZoomBase: CGFloat = 1.0  // zoom at gesture start
    @State private var safeAreaInsets: EdgeInsets = .init()

    var body: some View {
        GeometryReader { geo in
            let pipWidth = geo.size.width * 0.28
            let pipHeight = pipWidth * (4.0 / 3.0)
            let pipSize = CGSize(width: pipWidth, height: pipHeight)

            ZStack {
                // Back camera: full-bleed primary layer (D-06)
                CameraPreviewView(previewLayer: cameraManager.backPreviewLayer)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                // Accumulate from baseline set at gesture start (D-09: clamp 1.0–3.0x)
                                let factor = activeZoomBase * scale
                                cameraManager.setZoom(factor)
                            }
                            .onEnded { scale in
                                // Save clamped zoom as new baseline for next gesture
                                let factor = min(max(activeZoomBase * scale, 1.0), 3.0)
                                activeZoomBase = factor
                                cameraManager.setZoom(factor)
                            }
                    )
                    .simultaneousGesture(
                        // Reset zoom baseline on two-finger tap (convenience reset)
                        TapGesture(count: 2)
                            .onEnded {
                                activeZoomBase = 1.0
                                cameraManager.setZoom(1.0)
                            }
                    )

                // Front camera PiP overlay: draggable (D-05, D-07)
                CameraPreviewView(previewLayer: cameraManager.frontPreviewLayer)
                    .frame(width: pipWidth, height: pipHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    // Apply PiP position: default top-right, then offset by drag state (D-05)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, geo.safeAreaInsets.top + PiPOverlayState.edgeMargin)
                    .padding(.trailing, PiPOverlayState.edgeMargin)
                    .offset(x: -pipState.offset.width, y: pipState.offset.height)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                pipState.updateDrag(
                                    translation: value.translation,
                                    containerSize: geo.size,
                                    pipSize: pipSize,
                                    safeAreaInsets: geo.safeAreaInsets
                                )
                            }
                            .onEnded { value in
                                pipState.endDrag(
                                    translation: value.translation,
                                    containerSize: geo.size,
                                    pipSize: pipSize,
                                    safeAreaInsets: geo.safeAreaInsets
                                )
                            }
                    )
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: pipState.offset)
            }
            .background(Color.black)
            .onAppear {
                safeAreaInsets = geo.safeAreaInsets
                // Sync zoom baseline to current device zoom (e.g. after app resume)
                activeZoomBase = cameraManager.backZoomFactor
            }
        }
        .ignoresSafeArea()
    }
}
