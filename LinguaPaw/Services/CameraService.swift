import AVFoundation
import UIKit

enum CameraError: LocalizedError {
    case captureFailed
    var errorDescription: String? { "Не удалось сделать снимок." }
}

/// Обёртка над AVCaptureSession: живой превью камеры, съёмка фото, фонарик.
/// Работает с задней широкоугольной камерой, разрешение запрашивается лениво,
/// при первом обращении к экрану «Камера».
@MainActor
final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var isTorchOn = false
    @Published var permissionDenied = false

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.SiaSoft.LinguaPaw.camera-session")
    private var photoContinuation: CheckedContinuation<UIImage, Error>?
    private var isConfigured = false

    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
            configureIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.permissionDenied = false
                        self.configureIfNeeded()
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else {
            sessionQueue.async { [session] in if !session.isRunning { session.startRunning() } }
            return
        }
        isConfigured = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchOn ? .off : .on
            isTorchOn.toggle()
            device.unlockForConfiguration()
        } catch { /* фонарик недоступен — молча игнорируем */ }
    }

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = isTorchOn ? .on : .off
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error {
                photoContinuation?.resume(throwing: error)
                photoContinuation = nil
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                photoContinuation?.resume(throwing: CameraError.captureFailed)
                photoContinuation = nil
                return
            }
            photoContinuation?.resume(returning: image)
            photoContinuation = nil
        }
    }
}
