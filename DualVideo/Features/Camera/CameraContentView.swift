import SwiftUI
import AVFoundation

struct CameraContentView: View {
    let cameraManager: CameraManager
    let recordingManager: RecordingManager

    @Environment(AppState.self) private var appState

    @State private var pipState = PiPOverlayState()
    @State private var activeZoomBase: CGFloat = 1.0  // zoom at gesture start
    @State private var safeAreaInsets: EdgeInsets = .init()
    @State private var showQualitySettings = false

    var body: some View {
        GeometryReader { geo in
            let pipWidth = geo.size.width * 0.28
            let pipHeight = pipWidth * (4.0 / 3.0)
            let pipSize = CGSize(width: pipWidth, height: pipHeight)

            ZStack {
                // Back camera: full-bleed primary layer (D-06)
                CameraPreviewView(previewLayer: cameraManager.backPreviewLayer)
                    .ignoresSafeArea()

                // Transparent gesture capture layer above UIViewRepresentable.
                // MagnificationGesture must be on a pure-SwiftUI view — UIViewRepresentable
                // intercepts UIKit touch events before SwiftUI's gesture recognizer fires.
                Color.clear
                    .contentShape(Rectangle())
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
                    .offset(x: pipState.offset.width, y: pipState.offset.height)
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

                // Recording counter — top-center, below Dynamic Island / notch
                if case .recording = recordingManager.phase {
                    VStack {
                        RecordingStatusOverlay(elapsedSeconds: recordingManager.elapsedSeconds)
                            .padding(.top, geo.safeAreaInsets.top + 40)
                            .transition(.opacity)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                // Bottom-leading: Torch toggle (D-03 — symmetric counterpart to quality button)
                VStack {
                    Spacer()
                    HStack {
                        TorchToggleButton(
                            isTorchOn: cameraManager.isTorchOn,
                            onTap: { cameraManager.toggleTorch() }
                        )
                        .padding(.leading, 20)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 28)
                        Spacer()
                    }
                }

                // Bottom-trailing: Quality settings button (LAYOUT-02)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        QualitySettingsButton(
                            isRecording: {
                                if case .recording = recordingManager.phase { return true }
                                return false
                            }(),
                            onTap: { showQualitySettings = true }
                        )
                        .padding(.trailing, 24)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 28)
                    }
                }

                // Bottom-center: Zoom presets above record button (LAYOUT-01)
                VStack(spacing: 12) {
                    Spacer()
                    ZoomPresetView(
                        currentZoom: cameraManager.backZoomFactor,
                        onPresetSelected: { factor in
                            cameraManager.setZoom(factor)
                            activeZoomBase = factor  // CRITICAL: sync pinch baseline (RESEARCH.md Pitfall 1)
                        }
                    )
                    // Transient success banner: appears 2.5s after successful save (OUT-02)
                    if case .success = recordingManager.saveResult {
                        Text("Saved to Photos")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .cameraGlassBackground(in: Capsule())
                            .padding(.bottom, 8)
                            .transition(.opacity)
                            .onAppear {
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                                    recordingManager.saveResult = nil
                                }
                            }
                    }
                    RecordButton(
                        isRecording: {
                            if case .recording = recordingManager.phase { return true }
                            return false
                        }(),
                        isFinalizing: {
                            if case .finalizing = recordingManager.phase { return true }
                            return false
                        }(),
                        onTap: {
                            if case .recording = recordingManager.phase {
                                recordingManager.stopRecording()
                            } else if case .idle = recordingManager.phase {
                                // Pass user's persisted quality selection (VQ-01, VQ-02, VQ-04)
                                recordingManager.startRecording(settings: appState.qualitySettings)
                            }
                        }
                    )
                    .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                }
            }
            .background(Color.black)
            .animation(.easeInOut(duration: 0.3), value: {
                if case .recording = recordingManager.phase { return 1 }
                return 0
            }())
            .onAppear {
                safeAreaInsets = geo.safeAreaInsets
                // Sync zoom baseline to current device zoom (e.g. after app resume)
                activeZoomBase = cameraManager.backZoomFactor
                // OUT-03: restore PiP to last-used corner using current screen geometry
                pipState.restorePersistedCorner(
                    containerSize: geo.size,
                    pipSize: pipSize,
                    safeAreaInsets: geo.safeAreaInsets
                )
            }
        }
        .ignoresSafeArea()
        .defersSystemGestures(on: .bottom)
        .onChange(of: cameraManager.isSessionRunning) { _, isRunning in
            if isRunning {
                Task { @MainActor in
                    recordingManager.setup(cameraManager: cameraManager)
                }
            }
        }
        .onChange(of: pipState.offset) { _, newOffset in
            Task { @MainActor in
                cameraManager.compositor?.updatePiPOffset(newOffset)
            }
        }
        // Save-failure alert: shown when saveResult is .failure (OUT-02, DEV-03)
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: {
                    if case .failure = recordingManager.saveResult { return true }
                    return false
                },
                set: { if !$0 { recordingManager.saveResult = nil } }
            ),
            actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    recordingManager.saveResult = nil
                }
                Button("Dismiss", role: .cancel) {
                    recordingManager.saveResult = nil
                }
            },
            message: {
                if case .failure(let err) = recordingManager.saveResult {
                    switch err {
                    case .permissionDenied:
                        Text("DualVideo doesn't have permission to save to Photos. Open Settings to allow access.")
                    case .saveFailed(let msg):
                        Text("Could not save recording: \(msg)")
                    }
                }
            }
        )
        // Quality settings sheet — glass presentation background (D-10, RESEARCH.md Pitfall 4)
        .sheet(isPresented: $showQualitySettings) {
            QualitySettingsSheet(
                settings: Binding(
                    get: { appState.qualitySettings },
                    set: { appState.qualitySettings = $0 }
                ),
                onDismiss: {
                    appState.qualitySettings.save()
                    // Apply updated resolution and frame rate to both cameras
                    cameraManager.applyResolutionFormat(resolution: appState.qualitySettings.resolution)
                    cameraManager.applyFrameRate(appState.qualitySettings.frameRate)
                }
            )
            .presentationBackground(.ultraThinMaterial)
        }
    }
}
