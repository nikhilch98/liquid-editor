// CameraCaptureSheet.swift
// LiquidEditor
//
// Full-screen camera capture modal (F6-5).
//
// Hosts an AVCaptureSession via a minimal UIViewRepresentable preview
// (AVCaptureVideoPreviewLayer has no SwiftUI equivalent yet). Provides
// front/back toggle, flash toggle, photo / video segment, and an 80pt
// shutter button. On successful capture the resulting temp-file URL is
// emitted via the `onCapture` callback.

import AVFoundation
import SwiftUI
import UIKit

// MARK: - CameraCaptureSheet

/// Modal camera-capture sheet.
@MainActor
struct CameraCaptureSheet: View {

    // MARK: - Inputs

    /// Permission coordinator used for the camera (and microphone for video).
    let permissions: PermissionCoordinator

    /// Invoked when the user captures media; URL points to a temp file.
    let onCapture: (URL) -> Void

    // MARK: - Mode

    enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
        case photo
        case video
        var id: String { rawValue }

        var title: String {
            switch self {
            case .photo: return "Photo"
            case .video: return "Video"
            }
        }
    }

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var controller = CameraCaptureController()
    @State private var authorized = false
    @State private var errorMessage: String?
    @State private var mode: CaptureMode = .photo

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if authorized {
                CameraPreviewView(session: controller.session)
                    .ignoresSafeArea()
            } else {
                permissionPrompt
            }

            VStack {
                topBar
                Spacer()
                controlBar
            }
            .padding(LiquidSpacing.lg)
        }
        .task {
            let camera = await permissions.requestCameraAccess()
            let mic = await permissions.requestMicrophoneAccess()
            authorized = camera
            guard camera else {
                errorMessage = "Camera access is required."
                return
            }
            do {
                try controller.configure(includeAudio: mic)
                controller.startSession()
            } catch {
                errorMessage = "Could not configure camera: \(error.localizedDescription)"
            }
        }
        .onDisappear {
            controller.stopSession()
        }
        .alert(
            "Camera",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { errorMessage = nil }
            },
            message: { Text(errorMessage ?? "") }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var permissionPrompt: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access required")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Enable camera access to capture photo or video.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(LiquidSpacing.xl)
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(LiquidSpacing.md)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close camera")

            Spacer()

            Button {
                controller.toggleFlash()
            } label: {
                Image(systemName: controller.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(controller.isFlashOn ? .yellow : .white)
                    .padding(LiquidSpacing.md)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(controller.isFlashOn ? "Flash on" : "Flash off")
        }
    }

    @ViewBuilder
    private var controlBar: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Picker("Mode", selection: $mode) {
                ForEach(CaptureMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            HStack {
                // Left spacer to balance the flip button
                Color.clear.frame(width: 52, height: 52)

                Spacer()

                // Shutter button: 80pt round, white border
                Button(action: shutterTapped) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(mode == .video && controller.isRecording ? Color.red : Color.white)
                            .frame(
                                width: mode == .video && controller.isRecording ? 32 : 68,
                                height: mode == .video && controller.isRecording ? 32 : 68
                            )
                            .animation(.easeInOut(duration: 0.2), value: controller.isRecording)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shutterAccessibilityLabel)
                .disabled(!authorized)

                Spacer()

                // Flip camera
                Button {
                    controller.flipCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Flip camera")
                .disabled(!authorized)
            }
        }
    }

    // MARK: - Actions

    private var shutterAccessibilityLabel: String {
        switch mode {
        case .photo: return "Take photo"
        case .video: return controller.isRecording ? "Stop recording" : "Start recording"
        }
    }

    private func shutterTapped() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        switch mode {
        case .photo:
            controller.capturePhoto { result in
                Task { @MainActor in
                    switch result {
                    case .success(let url):
                        onCapture(url)
                        dismiss()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            }
        case .video:
            if controller.isRecording {
                controller.stopVideoRecording { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let url):
                            onCapture(url)
                            dismiss()
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } else {
                do {
                    try controller.startVideoRecording()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - CameraPreviewView

/// `UIViewRepresentable` wrapper for an `AVCaptureVideoPreviewLayer`.
/// SwiftUI has no native preview for AVFoundation, so a thin UIKit
/// bridge is required here.
private struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - CameraCaptureController

/// Observable capture controller bridging the SwiftUI sheet and AVFoundation.
@MainActor
@Observable
final class CameraCaptureController: NSObject {

    // MARK: - Observable state

    private(set) var isFlashOn = false
    private(set) var isRecording = false

    // MARK: - Session

    let session = AVCaptureSession()

    // MARK: - Private

    @ObservationIgnored
    private let photoOutput = AVCapturePhotoOutput()

    @ObservationIgnored
    private let movieOutput = AVCaptureMovieFileOutput()

    @ObservationIgnored
    private var currentVideoInput: AVCaptureDeviceInput?

    @ObservationIgnored
    private var currentPosition: AVCaptureDevice.Position = .back

    @ObservationIgnored
    private var photoContinuation: ((Result<URL, Error>) -> Void)?

    @ObservationIgnored
    private var videoContinuation: ((Result<URL, Error>) -> Void)?

    /// Dedicated serial queue for session start/stop (AVCaptureSession
    /// operations block and must not be on the main queue).
    @ObservationIgnored
    private let sessionQueue = DispatchQueue(label: "com.liquideditor.camera.session")

    // MARK: - Configuration

    enum CameraError: LocalizedError {
        case noDevice
        case cannotAddInput
        case cannotAddOutput
        case notRecording
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .noDevice: return "No camera available."
            case .cannotAddInput: return "Cannot attach camera input."
            case .cannotAddOutput: return "Cannot attach capture output."
            case .notRecording: return "Not currently recording."
            case .captureFailed: return "Capture failed."
            }
        }
    }

    /// Configure the session with video + optional audio.
    func configure(includeAudio: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        // Video input
        let videoInput = try makeVideoInput(position: .back)
        guard session.canAddInput(videoInput) else { throw CameraError.cannotAddInput }
        session.addInput(videoInput)
        currentVideoInput = videoInput
        currentPosition = .back

        // Audio input (optional)
        if includeAudio, let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        // Photo output
        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)

        // Movie output
        guard session.canAddOutput(movieOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(movieOutput)
    }

    func startSession() {
        guard !session.isRunning else { return }
        let session = self.session
        nonisolated(unsafe) let box = session
        sessionQueue.async {
            box.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        let session = self.session
        nonisolated(unsafe) let box = session
        sessionQueue.async {
            box.stopRunning()
        }
    }

    // MARK: - Toggles

    func toggleFlash() {
        isFlashOn.toggle()
    }

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back
        guard let newInput = try? makeVideoInput(position: newPosition) else { return }
        session.beginConfiguration()
        if let current = currentVideoInput {
            session.removeInput(current)
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentVideoInput = newInput
            currentPosition = newPosition
        } else if let current = currentVideoInput {
            session.addInput(current)
        }
        session.commitConfiguration()
    }

    // MARK: - Capture

    func capturePhoto(completion: @escaping (Result<URL, Error>) -> Void) {
        photoContinuation = completion
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.on), isFlashOn {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startVideoRecording() throws {
        guard !movieOutput.isRecording else { return }
        // Torch approximates flash for video.
        if let device = currentVideoInput?.device, device.hasTorch {
            try? device.lockForConfiguration()
            device.torchMode = isFlashOn ? .on : .off
            device.unlockForConfiguration()
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
    }

    func stopVideoRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        guard movieOutput.isRecording else {
            completion(.failure(CameraError.notRecording))
            return
        }
        videoContinuation = completion
        movieOutput.stopRecording()
    }

    // MARK: - Helpers

    private func makeVideoInput(position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position
            )
        else {
            throw CameraError.noDevice
        }
        return try AVCaptureDeviceInput(device: device)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraCaptureController: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.photoContinuation = nil }
            if let error {
                self.photoContinuation?(.failure(error))
                return
            }
            guard let data else {
                self.photoContinuation?(.failure(CameraError.captureFailed))
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("photo-\(UUID().uuidString).jpg")
            do {
                try data.write(to: url, options: .atomic)
                self.photoContinuation?(.success(url))
            } catch {
                self.photoContinuation?(.failure(error))
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraCaptureController: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.videoContinuation = nil }
            self.isRecording = false
            if let error {
                self.videoContinuation?(.failure(error))
            } else {
                self.videoContinuation?(.success(outputFileURL))
            }
        }
    }
}
