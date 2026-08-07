//
//  WebcamManager.swift
//  FunNotch
//
//  Drives the "mirror" — a live front-camera preview inside the open notch.
//  The session only runs while the mirror is actually visible so the camera
//  light is never on for longer than it needs to be.
//

import AVFoundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class WebcamManager: NSObject, ObservableObject {
    static let shared = WebcamManager()

    @Published private(set) var isRunning = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published private(set) var hasCamera = false

    let session = AVCaptureSession()
    // Touched only on `sessionQueue`, never concurrently.
    nonisolated(unsafe) private var input: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.funnotch.camera")

    private override init() {
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCamera = AVCaptureDevice.default(for: .video) != nil
    }

    func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationStatus = .authorized
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.authorizationStatus = granted ? .authorized : .denied
                        completion(granted)
                    }
                }
            }
        default:
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            completion(false)
        }
    }

    func start() {
        requestAccessIfNeeded { [weak self] granted in
            guard granted, let self else { return }
            self.configureAndRun()
        }
    }

    private func configureAndRun() {
        guard !isRunning else { return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            hasCamera = false
            return
        }
        hasCamera = true

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            if self.input == nil, let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.input = input
            }

            self.session.commitConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.isRunning = true }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}

/// Hosts the AVFoundation preview layer inside SwiftUI.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(previewLayer)
            // Mirror horizontally so it behaves like a real mirror.
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
