import AVFoundation
import Vision
import UIKit

/// Live body pose from the camera, for the live form check.
final class PoseDetectionService: NSObject, ObservableObject {

    /// Joints of the person nearest the camera, in Vision's normalized
    /// coordinates (origin bottom-left) — for drawing.
    @Published var joints: [BodyJoint: CGPoint] = [:]
    @Published var isPersonDetected = false
    /// Width / height of the camera frames, for aspect-correct angles and
    /// for placing the skeleton on the aspect-filled preview.
    @Published var aspect: CGFloat = 9.0 / 16.0

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "sb.pose.processing", qos: .userInteractive)
    private var configured = false

    // MARK: - Setup

    func setup(front: Bool = true) {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: front ? .front : .back
        ), let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Fix orientation for portrait
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if front { connection.isVideoMirrored = true }
        }

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        processingQueue.async { self.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        processingQueue.async { self.session.stopRunning() }
    }
}

// MARK: - Sample Buffer Delegate

extension PoseDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        var aspect: CGFloat = 9.0 / 16.0
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
            if w > 0, h > 0 { aspect = CGFloat(w) / CGFloat(h) }
        }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        var best: [BodyJoint: CGPoint] = [:]
        if (try? handler.perform([request])) != nil {
            // In a gym there are often other people in the frame: follow
            // the one nearest the camera, which is the biggest.
            var bestArea: CGFloat = 0
            for observation in request.results ?? [] {
                guard let all = try? observation.recognizedPoints(.all) else { continue }
                var points: [BodyJoint: CGPoint] = [:]
                for (name, p) in all where p.confidence >= 0.3 {
                    if let joint = VideoPoseExtractor.map[name] { points[joint] = p.location }
                }
                let xs = points.values.map(\.x), ys = points.values.map(\.y)
                guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { continue }
                let area = (maxX - minX) * (maxY - minY)
                if area > bestArea { bestArea = area; best = points }
            }
        }
        DispatchQueue.main.async {
            self.aspect = aspect
            self.isPersonDetected = !best.isEmpty
            self.joints = best
        }
    }
}
