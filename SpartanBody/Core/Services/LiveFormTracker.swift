import Foundation
import CoreGraphics

/// Live form check: the camera's poses go into a rolling buffer and the same
/// engine as the video analysis reviews each rep as soon as it finishes.
///
/// The old live analyzer judged single frames, so it flashed "go lower" on
/// the way down of every rep, only looked at the left side, measured angles
/// on the squashed portrait image, and counted reps by a joint going *down*
/// — curls and presses, where the wrist goes up, never counted.
struct LiveFormTracker {

    /// What the screen shows. Keys are localized by the view.
    struct Feedback: Equatable {
        enum State { case position, ready, good, fix, hold }
        var state: State
        var titleKey: String
        var detail: String
        var badJoints: Set<BodyJoint> = []
        var isGood: Bool { state == .ready || state == .good || state == .hold }
    }

    private(set) var exercise: VideoExercise
    private(set) var frames: [PoseFrame] = []
    /// Reps whose frames were dropped from the buffer on long sets.
    private var countedBefore = 0
    private var lastReport: FormReport?

    /// The engine was built and tested at 12 frames a second.
    static let fps: Double = 12
    /// A set rarely lasts longer; older frames are dropped.
    static let window: Double = 90

    init(exercise: VideoExercise) { self.exercise = exercise }

    var reps: Int { countedBefore + (lastReport?.reps.count ?? 0) }

    /// Adds a frame; points are aspect-corrected like PoseFrame's.
    /// Returns false when the frame came too soon after the previous one.
    @discardableResult
    mutating func add(_ points: [BodyJoint: CGPoint], at time: Double) -> Bool {
        if let last = frames.last, time - last.time < 1 / Self.fps { return false }
        frames.append(PoseFrame(time: time, points: points))
        if let first = frames.first, time - first.time > Self.window { dropOldest(before: time - Self.window / 2) }
        return true
    }

    mutating func analyze() -> Feedback {
        guard let last = frames.last, !last.points.isEmpty else { return Self.position }
        let result = VideoFormEngine.analyze(frames, exercise: exercise, live: true)
        switch result {
        case .failure(.bodyNotVisible):
            // The first second or two, before enough frames exist.
            return frames.count < 24 ? ready : Self.position
        case .failure(.noReps):
            return ready
        case .success(let report):
            lastReport = report
            if exercise.isHold {
                if let issue = report.issues.first { return fix(issue.rule) }
                return Feedback(state: .hold, titleKey: "form.live.hold",
                                detail: String(format: NSLocalizedString("form.live.holdSeconds %lld", comment: ""),
                                               Int((report.holdSeconds ?? 0).rounded())))
            }
            guard let rep = report.reps.last else { return ready }
            if let rule = rep.issues.first { return fix(rule) }
            return Feedback(state: .good, titleKey: "form.live.goodRep",
                            detail: String(format: NSLocalizedString("form.live.repScore %lld %lld", comment: ""),
                                           reps, rep.score))
        }
    }

    private var ready: Feedback {
        Feedback(state: .ready, titleKey: "form.live.ready", detail: NSLocalizedString(exercise.cameraKey, comment: ""))
    }

    static let position = Feedback(state: .position, titleKey: "form.live.position",
                                   detail: NSLocalizedString("form.live.positionDetail", comment: ""))

    private func fix(_ rule: String) -> Feedback {
        Feedback(state: .fix, titleKey: "form.rule.\(rule).title",
                 detail: NSLocalizedString("form.rule.\(rule).fix", comment: ""), badJoints: Self.joints(for: rule))
    }

    /// Keeps the reps already finished before `cutoff` in the count.
    private mutating func dropOldest(before cutoff: Double) {
        countedBefore += lastReport?.reps.filter { $0.end < cutoff }.count ?? 0
        frames.removeAll { $0.time < cutoff }
        lastReport = nil
    }

    /// The joints to draw in red for a rule.
    static func joints(for rule: String) -> Set<BodyJoint> {
        let knees: Set<BodyJoint> = [.leftKnee, .rightKnee]
        let hips: Set<BodyJoint> = [.leftHip, .rightHip]
        let elbows: Set<BodyJoint> = [.leftElbow, .rightElbow]
        let torso: Set<BodyJoint> = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        switch rule {
        case "squat.depth", "lunge.depth", "rdl.knees", "deadlift.squatting", "warrior.knee", "dog.legs", "tree.leg":
            return knees
        case "pushup.sag", "pushup.pike", "plank.sag", "plank.pike", "deadlift.lockout", "deadlift.hipsFirst",
             "rdl.range", "dog.hips", "squat.lockout", "pullup.kip", "tree.balance":
            return hips
        case "squat.chest", "ohp.lean", "lunge.torso", "curl.swing", "warrior.torso", "tree.torso":
            return torso
        case "tempo.fast":
            return []
        default:
            return elbows
        }
    }
}
