//
//  CameraManager.swift
//  DataTransmission
//
//  AVFoundation camera wrapper.  Captures a single photo on demand
//  (no live barcode / code detection).
//

import AVFoundation
import Combine
import UIKit
import SwiftUI

/// A simple camera manager that provides a live preview layer and
/// captures a still photo on demand.
class CameraManager: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var isAuthorized = false
    @Published var error: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    override init() {
        super.init()
    }

    // MARK: - Setup

    func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configureSession() }
                    else { self?.error = "Camera access denied." }
                }
            }
        default:
            error = "Camera access denied. Please enable in Settings."
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            error = "Unable to access back camera."
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            error = "Unable to add photo output."
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() async -> UIImage? {
        return await withCheckedContinuation { cont in
            self.continuation = cont
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stop() {
        session.stopRunning()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        }
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
            self?.continuation?.resume(returning: image)
            self?.continuation = nil
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
