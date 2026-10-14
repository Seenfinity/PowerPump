import AVFoundation
import Vision
import CoreGraphics

/// Reads a recorded video and returns the body pose in each sampled frame.
/// Runs on the device — the video never leaves the phone.
struct VideoPoseExtractor {

    struct Output {
        var frames: [PoseFrame]
        /// Width / height of the upright video. PoseFrame x values are
        /// multiplied by this; divide it back out to draw on screen.
        var aspect: CGFloat
        var duration: Double
    }

    enum Failure: Error { case unreadable, tooShort }

    /// Longest stretch analysed. A set rarely lasts longer, and it keeps the
    /// analysis to a few seconds.
    static let maxSeconds: Double = 60
    static let fps: Double = 12

    /// - Parameter progress: 0–1, called on the main actor.
    static func extract(from url: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> Output {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 1 else { throw Failure.tooShort }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.unreadable }

        // Upright size: the preferred transform rotates portrait phone video.
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let upright = natural.applying(transform)
        let w = abs(upright.width), h = abs(upright.height)
        guard w > 0, h > 0 else { throw Failure.unreadable }
        let aspect = w / h

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Vision doesn't need full resolution; smaller frames are much faster.
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let end = min(duration, maxSeconds)
        let times = Array(stride(from: 0.0, to: end, by: 1 / fps))
        var frames: [PoseFrame] = []
        frames.reserveCapacity(times.count)

        for (i, t) in times.enumerated() {
            try Task.checkCancellation()
            if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image {
                frames.append(PoseFrame(time: t, points: pose(in: image, aspect: aspect)))
            }
            if i % 4 == 0 { await progress(Double(i + 1) / Double(times.count)) }
        }
        await progress(1)
        return Output(frames: frames, aspect: aspect, duration: end)
    }

    /// The pose of the person nearest the camera. A gym video often has
    /// other people in the background; the nearest is the biggest.
    private static func pose(in image: CGImage, aspect: CGFloat) -> [BodyJoint: CGPoint] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else { return [:] }

        func joints(_ o: VNHumanBodyPoseObservation) -> [BodyJoint: CGPoint] {
            guard let all = try? o.recognizedPoints(.all) else { return [:] }
            var out: [BodyJoint: CGPoint] = [:]
            for (name, point) in all where point.confidence >= 0.3 {
                guard let joint = map[name] else { continue }
                // Aspect-correct x so angles are true to the picture.
                out[joint] = CGPoint(x: point.location.x * aspect, y: point.location.y)
            }
            return out
        }
        func size(_ j: [BodyJoint: CGPoint]) -> CGFloat {
            guard let minX = j.values.map(\.x).min(), let maxX = j.values.map(\.x).max(),
                  let minY = j.values.map(\.y).min(), let maxY = j.values.map(\.y).max() else { return 0 }
            return (maxX - minX) * (maxY - minY)
        }
        return observations.map(joints).max { size($0) < size($1) } ?? [:]
    }

    static let map: [VNHumanBodyPoseObservation.JointName: BodyJoint] = [
        .nose: .nose, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]
}

// MARK: - History

/// Past analyses — the numbers only. The video itself is never stored.
@MainActor
final class FormReportStore: ObservableObject {
    static let shared = FormReportStore()
    @Published private(set) var reports: [FormReport] = []
    private let key = "sb_form_reports"

    private init() {
        reports = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([FormReport].self, from: $0) } ?? []
    }

    func add(_ r: FormReport) {
        reports.insert(r, at: 0)
        if reports.count > 100 { reports.removeLast(reports.count - 100) }
        if let data = try? JSONEncoder().encode(reports) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// The previous analysis of the same exercise, to compare against.
    func previous(to r: FormReport) -> FormReport? {
        reports.first { $0.exercise == r.exercise && $0.date < r.date }
    }
}
