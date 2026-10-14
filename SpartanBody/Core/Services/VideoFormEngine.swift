import Foundation
import CoreGraphics

// Form analysis of a recorded set, run entirely on the device.
//
// VideoPoseExtractor turns the video into PoseFrames (Vision); this file is the
// pure part: pick the visible side of the body, split the set into reps,
// check each rep against the exercise's rules and write a report. Kept free
// of Vision and UIKit so every rule can be tested with synthetic movements.

// MARK: - Pose input

enum BodyJoint: String, CaseIterable, Codable {
    case nose, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// One sampled frame. Points are aspect-corrected — x is scaled by the
/// frame's width/height ratio so angles measure what they look like, and y
/// grows upwards (Vision's convention). A portrait video measured in raw
/// normalized coordinates squashes every angle.
struct PoseFrame {
    var time: Double
    var points: [BodyJoint: CGPoint]
}

// MARK: - Exercises

enum FormCategory: String, CaseIterable, Identifiable {
    case gym, calisthenics, yoga
    var id: String { rawValue }
    var labelKey: String { "form.category.\(rawValue)" }
}

enum VideoExercise: String, CaseIterable, Codable, Identifiable {
    case squat, deadlift, romanianDeadlift, overheadPress, bicepCurl, lunge
    case pushUp, pullUp, dip, plank
    case warrior2, downwardDog, treePose

    var id: String { rawValue }

    var category: FormCategory {
        switch self {
        case .squat, .deadlift, .romanianDeadlift, .overheadPress, .bicepCurl, .lunge: return .gym
        case .pushUp, .pullUp, .dip, .plank: return .calisthenics
        case .warrior2, .downwardDog, .treePose: return .yoga
        }
    }

    var nameKey: String { "form.ex.\(rawValue)" }

    var icon: String {
        switch self {
        case .squat, .lunge:                      return "figure.strengthtraining.functional"
        case .deadlift, .romanianDeadlift:        return "figure.strengthtraining.traditional"
        case .overheadPress:                      return "figure.arms.open"
        case .bicepCurl:                          return "dumbbell.fill"
        case .pushUp, .plank:                     return "figure.core.training"
        case .pullUp:                             return "figure.climbing"
        case .dip:                                return "figure.cross.training"
        case .warrior2, .downwardDog, .treePose:  return "figure.yoga"
        }
    }

    /// Most lifts are judged in profile; the yoga poses and the pull-up read
    /// better from the front.
    var needsSideView: Bool {
        switch self {
        case .warrior2, .treePose, .pullUp: return false
        default: return true
        }
    }

    var isHold: Bool {
        switch self {
        case .plank, .warrior2, .downwardDog, .treePose: return true
        default: return false
        }
    }

    var cameraKey: String { needsSideView ? "form.camera.side" : "form.camera.front" }
}

// MARK: - Report

struct FormIssue: Codable, Identifiable, Equatable {
    var id: String { rule }
    /// Rule id; the UI shows "form.rule.<id>.title" and ".fix".
    var rule: String
    /// Reps where it happened (1-based). Empty for holds.
    var reps: [Int]
    /// Share of the set (or of the hold) affected, 0–1.
    var share: Double
}

struct RepResult: Codable, Equatable {
    var number: Int
    var start: Double
    var end: Double
    var peakTime: Double
    var score: Int
    var issues: [String]
}

struct FormReport: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var exercise: VideoExercise
    var date: Date = .now
    var score: Int
    var reps: [RepResult]
    var holdSeconds: Double?
    /// Most important first, at most three.
    var issues: [FormIssue]
    /// Form got clearly worse in the second half of the set.
    var fatigue: Bool
    /// Camera problems worth telling the user about.
    var warnings: [String]
    /// Which side of the body was analysed.
    var side: String

    var worstRep: RepResult? {
        reps.filter { !$0.issues.isEmpty }.min { $0.score < $1.score }
    }
}

enum FormAnalysisError: Error, Equatable {
    /// The body wasn't visible in enough frames.
    case bodyNotVisible
    /// Nothing that looks like a rep of this exercise.
    case noReps
}

// MARK: - Engine

enum VideoFormEngine {

    /// - Parameter live: the set is still going. A rep that hasn't come back
    ///   to the rest position yet is left out instead of judged unfinished.
    static func analyze(_ frames: [PoseFrame], exercise ex: VideoExercise,
                        live: Bool = false) -> Result<FormReport, FormAnalysisError> {
        guard frames.count >= 5 else { return .failure(.bodyNotVisible) }
        let side = bestSide(frames, exercise: ex)
        let metrics = frames.map { Metrics(frame: $0, side: side) }
        let valid = metrics.filter { spec(ex).isValid($0) }
        guard Double(valid.count) / Double(metrics.count) >= 0.4 else { return .failure(.bodyNotVisible) }

        var warnings: [String] = []
        if Double(valid.count) / Double(metrics.count) < 0.7 { warnings.append("form.warn.partial") }
        if ex.needsSideView, isFilmedFromFront(valid) { warnings.append("form.warn.front") }

        return ex.isHold
            ? analyzeHold(valid, ex, side: side, warnings: warnings)
            : analyzeReps(valid, ex, side: side, warnings: warnings, live: live)
    }

    // MARK: Reps

    private static func analyzeReps(_ m: [Metrics], _ ex: VideoExercise, side: Side,
                                    warnings: [String], live: Bool = false) -> Result<FormReport, FormAnalysisError> {
        let s = spec(ex)
        let signal = smooth(m.map { s.primary($0) ?? .nan })
        let windows = segment(signal, times: m.map(\.time), spec: s, includeUnfinished: !live)
        guard !windows.isEmpty else { return .failure(.noReps) }

        var reps: [RepResult] = []
        for (n, w) in windows.enumerated() {
            let slice = RepSlice(frames: Array(m[w.range]), peak: w.peak - w.range.lowerBound)
            let broken = s.rules.filter { $0.violated(slice) }
            let penalty = min(broken.reduce(0) { $0 + $1.weight }, 100)
            reps.append(RepResult(number: n + 1, start: m[w.range.lowerBound].time,
                                  end: m[w.range.upperBound].time, peakTime: m[w.peak].time,
                                  score: 100 - penalty, issues: broken.map(\.id)))
        }

        var issues: [FormIssue] = s.rules.compactMap { rule in
            let hit = reps.filter { $0.issues.contains(rule.id) }.map(\.number)
            let share = Double(hit.count) / Double(reps.count)
            // One bad rep in eight is noise; a third of the set is a habit.
            return share >= 0.3 || (reps.count <= 3 && !hit.isEmpty)
                ? FormIssue(rule: rule.id, reps: hit, share: share) : nil
        }
        let weights = Dictionary(uniqueKeysWithValues: s.rules.map { ($0.id, $0.weight) })
        issues.sort { $0.share * Double(weights[$0.rule]!) > $1.share * Double(weights[$1.rule]!) }

        // Fatigue: the back half of the set clearly worse than the front.
        var fatigue = false
        if reps.count >= 4 {
            let half = reps.count / 2
            let front = Double(reps.prefix(half).reduce(0) { $0 + $1.score }) / Double(half)
            let back = Double(reps.suffix(reps.count - half).reduce(0) { $0 + $1.score }) / Double(reps.count - half)
            fatigue = front - back >= 20
        }

        let score = reps.reduce(0) { $0 + $1.score } / reps.count
        return .success(FormReport(exercise: ex, score: score, reps: reps, holdSeconds: nil,
                                   issues: Array(issues.prefix(3)), fatigue: fatigue,
                                   warnings: warnings, side: side.name))
    }

    struct RepWindow { var range: ClosedRange<Int>; var peak: Int }

    /// Splits the set into reps with two thresholds (hysteresis), so jitter
    /// around one line can't count twice. A rep is one visit to the "work"
    /// phase — the bottom of a squat, the lockout of a deadlift — framed by
    /// the opposite phase on each side (or the end of the video).
    static func segment(_ signal: [Double], times: [Double], spec s: ExerciseSpec,
                        includeUnfinished: Bool = true) -> [RepWindow] {
        enum Phase { case flexed, extended, middle }
        func phase(_ v: Double) -> Phase {
            v.isNaN ? .middle : v <= s.flexed ? .flexed : v >= s.extended ? .extended : .middle
        }
        let work: Phase = s.workFlexed ? .flexed : .extended
        let rest: Phase = s.workFlexed ? .extended : .flexed

        var windows: [RepWindow] = []
        var lastRest: Int? = nil       // most recent frame in the rest phase
        var workStart: Int? = nil
        var inWork = false
        for i in signal.indices {
            let p = phase(signal[i])
            if p == rest {
                if inWork, let ws = workStart, let lr = lastRest {
                    windows.append(window(signal, from: lr, to: i, workFrom: ws, flexed: s.workFlexed))
                    inWork = false
                }
                lastRest = i
            } else if p == work, !inWork, lastRest != nil {
                inWork = true; workStart = i
            }
        }
        // Set ends in the work phase (deadlift lockout, last curl held).
        if includeUnfinished, inWork, let ws = workStart, let lr = lastRest, signal.count - 1 > ws {
            windows.append(window(signal, from: lr, to: signal.count - 1, workFrom: ws, flexed: s.workFlexed))
        }
        // Too short to be a real rep: a twitch across both lines.
        var reps = windows.filter { times[$0.range.upperBound] - times[$0.range.lowerBound] >= 0.5 }

        // Each window spans threshold to threshold, which cuts off the full
        // stand (or full hang) either side of the rep — so a lockout rule
        // would fail every good rep. Widen each window to the middle of the
        // rest between reps, and to the ends of the video for the first and
        // last one.
        for k in reps.indices {
            let lo = k == 0 ? 0 : (reps[k - 1].range.upperBound + reps[k].range.lowerBound) / 2
            let hi = k == reps.count - 1 ? signal.count - 1
                : (reps[k].range.upperBound + reps[k + 1].range.lowerBound) / 2
            reps[k].range = min(lo, reps[k].range.lowerBound)...max(hi, reps[k].range.upperBound)
        }
        return reps
    }

    private static func window(_ sig: [Double], from a: Int, to b: Int, workFrom w: Int, flexed: Bool) -> RepWindow {
        let span = w...b
        let peak = span.filter { !sig[$0].isNaN }
            .min { flexed ? sig[$0] < sig[$1] : sig[$0] > sig[$1] } ?? w
        return RepWindow(range: a...b, peak: peak)
    }

    // MARK: Holds

    private static func analyzeHold(_ m: [Metrics], _ ex: VideoExercise, side: Side,
                                    warnings: [String]) -> Result<FormReport, FormAnalysisError> {
        let s = spec(ex)
        let inPose = m.filter { s.inPose?($0) ?? true }
        guard inPose.count >= 5, let first = inPose.first, let last = inPose.last else {
            return .failure(.noReps)
        }
        let slice = RepSlice(frames: inPose, peak: inPose.count / 2)
        var issues: [FormIssue] = []
        var penalty = 0
        for rule in s.rules {
            let share = rule.share?(slice) ?? (rule.violated(slice) ? 1 : 0)
            if share >= 0.3 {
                issues.append(FormIssue(rule: rule.id, reps: [], share: share))
                penalty += Int(Double(rule.weight) * share)
            }
        }
        let weights = Dictionary(uniqueKeysWithValues: s.rules.map { ($0.id, $0.weight) })
        issues.sort { $0.share * Double(weights[$0.rule]!) > $1.share * Double(weights[$1.rule]!) }
        return .success(FormReport(exercise: ex, score: max(100 - penalty, 0), reps: [],
                                   holdSeconds: last.time - first.time, issues: Array(issues.prefix(3)),
                                   fatigue: false, warnings: warnings, side: side.name))
    }

    // MARK: Camera

    /// Shoulders far apart relative to the torso means the camera sees the
    /// chest, not the profile — depth and back angle can't be read that way.
    private static func isFilmedFromFront(_ m: [Metrics]) -> Bool {
        let ratios = m.compactMap(\.shoulderSpread).sorted()
        guard !ratios.isEmpty else { return false }
        return ratios[ratios.count / 2] > 0.55
    }

    // MARK: Side

    struct Side {
        var name: String
        var shoulder, elbow, wrist, hip, knee, ankle: BodyJoint
        static let left = Side(name: "left", shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist,
                               hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle)
        static let right = Side(name: "right", shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist,
                                hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle)
    }

    /// The side nearer the camera is the one Vision sees in more frames.
    static func bestSide(_ frames: [PoseFrame], exercise: VideoExercise) -> Side {
        func count(_ s: Side) -> Int {
            frames.filter { f in [s.shoulder, s.elbow, s.wrist, s.hip, s.knee, s.ankle]
                .allSatisfy { f.points[$0] != nil } }.count
        }
        return count(.right) > count(.left) ? .right : .left
    }

    // MARK: Helpers

    private static func smooth(_ x: [Double]) -> [Double] {
        x.indices.map { i in
            let w = x[max(0, i - 1)...min(x.count - 1, i + 1)].filter { !$0.isNaN }
            return w.isEmpty ? .nan : w.reduce(0, +) / Double(w.count)
        }
    }
}

// MARK: - Per-frame measurements

/// Everything the rules look at in one frame, for the analysed side.
/// Angles in degrees; distances relative to torso length so they don't
/// depend on how far the camera is.
struct Metrics {
    var time: Double
    var knee: Double?          // hip–knee–ankle (180 = straight leg)
    var hip: Double?           // shoulder–hip–knee (180 = standing tall)
    var elbow: Double?         // shoulder–elbow–wrist
    var torsoLean: Double?     // shoulder–hip line from vertical
    var bodyLine: Double?      // shoulder–hip–ankle
    /// Hip above (+) or below (−) the shoulder–ankle line, per torso length.
    var hipOffset: Double?
    /// Elbow forward/back of the shoulder, per torso length.
    var elbowDrift: Double?
    /// Nose above (+) the wrists, per torso length (pull-up height).
    var noseOverWrists: Double?
    var hipX: Double?
    /// Both knees: the more bent one is the front leg in a lunge or warrior.
    var frontKnee: Double?
    var backKnee: Double?
    /// Wrists' height difference from the shoulders, per torso length.
    var armsLevel: Double?
    var shoulderSpread: Double?
    /// Shoulder–ankle line from horizontal: ~0 lying (plank), ~90 standing.
    var bodyTilt: Double?

    init(frame f: PoseFrame, side s: VideoFormEngine.Side) {
        time = f.time
        let p = f.points
        func ang(_ a: BodyJoint, _ b: BodyJoint, _ c: BodyJoint) -> Double? {
            guard let a = p[a], let b = p[b], let c = p[c] else { return nil }
            return Self.angle(a, b, c)
        }
        let torso: Double? = {
            guard let sh = p[s.shoulder], let hp = p[s.hip] else { return nil }
            let d = hypot(sh.x - hp.x, sh.y - hp.y)
            return d > 0.01 ? Double(d) : nil
        }()
        knee = ang(s.hip, s.knee, s.ankle)
        hip = ang(s.shoulder, s.hip, s.knee)
        elbow = ang(s.shoulder, s.elbow, s.wrist)
        bodyLine = ang(s.shoulder, s.hip, s.ankle)
        if let sh = p[s.shoulder], let an = p[s.ankle] {
            bodyTilt = abs(atan2(Double(sh.y - an.y), abs(Double(sh.x - an.x)))) * 180 / .pi
        }
        if let sh = p[s.shoulder], let hp = p[s.hip] {
            torsoLean = abs(atan2(Double(sh.x - hp.x), Double(sh.y - hp.y))) * 180 / .pi
            hipX = Double(hp.x)
        }
        if let t = torso, let sh = p[s.shoulder], let hp = p[s.hip], let an = p[s.ankle], abs(an.x - sh.x) > 0.02 {
            // Height of the shoulder–ankle line under the hip.
            let k = (hp.x - sh.x) / (an.x - sh.x)
            let lineY = sh.y + k * (an.y - sh.y)
            hipOffset = Double(hp.y - lineY) / t
        }
        if let t = torso, let sh = p[s.shoulder], let el = p[s.elbow] {
            elbowDrift = abs(Double(el.x - sh.x)) / t
        }
        let wristYs = [p[.leftWrist]?.y, p[.rightWrist]?.y].compactMap { $0 }
        if let t = torso, let n = p[.nose], !wristYs.isEmpty {
            let wy = wristYs.reduce(0, +) / CGFloat(wristYs.count)
            noseOverWrists = Double(n.y - wy) / t
        }
        let lk = ang(.leftHip, .leftKnee, .leftAnkle), rk = ang(.rightHip, .rightKnee, .rightAnkle)
        if let lk, let rk { frontKnee = min(lk, rk); backKnee = max(lk, rk) }
        if let t = torso {
            let pairs: [(BodyJoint, BodyJoint)] = [(.leftWrist, .leftShoulder), (.rightWrist, .rightShoulder)]
            let d = pairs.compactMap { w, sh -> Double? in
                guard let w = p[w], let sh = p[sh] else { return nil }
                return abs(Double(w.y - sh.y)) / t
            }
            if !d.isEmpty { armsLevel = d.reduce(0, +) / Double(d.count) }
            if let a = p[.leftShoulder], let b = p[.rightShoulder] {
                shoulderSpread = abs(Double(a.x - b.x)) / t
            }
        }
    }

    static func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let v1 = (Double(a.x - b.x), Double(a.y - b.y)), v2 = (Double(c.x - b.x), Double(c.y - b.y))
        let mag = hypot(v1.0, v1.1) * hypot(v2.0, v2.1)
        guard mag > 0 else { return 0 }
        return acos(max(-1, min(1, (v1.0 * v2.0 + v1.1 * v2.1) / mag))) * 180 / .pi
    }
}

/// One rep (or a whole hold) for the rules to look at.
struct RepSlice {
    var frames: [Metrics]
    var peak: Int
    var peakFrame: Metrics { frames[peak] }

    func values(_ k: KeyPath<Metrics, Double?>) -> [Double] { frames.compactMap { $0[keyPath: k] } }
    func max(_ k: KeyPath<Metrics, Double?>) -> Double? { values(k).max() }
    func min(_ k: KeyPath<Metrics, Double?>) -> Double? { values(k).min() }
    func range(_ k: KeyPath<Metrics, Double?>) -> Double? {
        guard let a = min(k), let b = max(k) else { return nil }
        return b - a
    }
    /// Share of frames where the condition holds (frames missing the value
    /// don't count either way).
    func share(_ k: KeyPath<Metrics, Double?>, _ test: (Double) -> Bool) -> Double {
        let v = values(k)
        return v.isEmpty ? 0 : Double(v.filter(test).count) / Double(v.count)
    }
    /// Seconds from the start of the rep to its peak — the lowering phase.
    var descent: Double { frames[peak].time - frames[0].time }
}

// MARK: - Rules

struct FormRule {
    var id: String
    /// 35 = changes what the exercise works; 20 = costs results or strains a
    /// joint; 10 = polish.
    var weight: Int
    var violated: (RepSlice) -> Bool
    /// For holds: share of the hold spent breaking the rule.
    var share: ((RepSlice) -> Double)? = nil
}

struct ExerciseSpec {
    var primary: (Metrics) -> Double?
    /// Primary-signal thresholds between which a rep travels.
    var flexed: Double
    var extended: Double
    /// Whether the rep's key moment is the flexed end (bottom of a squat) or
    /// the extended end (lockout of a deadlift).
    var workFlexed: Bool
    var required: [KeyPath<Metrics, Double?>]
    var rules: [FormRule]
    var inPose: ((Metrics) -> Bool)? = nil

    func isValid(_ m: Metrics) -> Bool { required.allSatisfy { m[keyPath: $0] != nil } }
}

extension VideoFormEngine {
    // Thresholds are for a 2-D side view. They're deliberately lenient: a
    // camera a few degrees off shouldn't make a good rep look bad.
    static func spec(_ ex: VideoExercise) -> ExerciseSpec {
        switch ex {
        case .squat:
            // Counting thresholds are loose on purpose: a half squat must
            // count as a rep so the depth rule can say so, instead of the
            // set coming back as "no reps".
            return ExerciseSpec(primary: { $0.knee }, flexed: 130, extended: 155, workFlexed: true,
                required: [\.knee, \.hip, \.torsoLean], rules: [
                FormRule(id: "squat.depth", weight: 35) { ($0.peakFrame.knee ?? 0) > 100 },
                FormRule(id: "squat.chest", weight: 20) { ($0.peakFrame.torsoLean ?? 0) > 50 },
                FormRule(id: "squat.lockout", weight: 10) { ($0.max(\.knee) ?? 180) < 160 },
                FormRule(id: "tempo.fast", weight: 10) { $0.descent < 0.5 },
            ])
        case .deadlift:
            return ExerciseSpec(primary: { $0.hip }, flexed: 120, extended: 158, workFlexed: false,
                required: [\.hip, \.knee, \.torsoLean], rules: [
                FormRule(id: "deadlift.lockout", weight: 20) { ($0.peakFrame.hip ?? 180) < 165 },
                FormRule(id: "deadlift.hipsFirst", weight: 35) { s in
                    // Knees straighten while the hips are still folded: the
                    // back ends up doing the lift.
                    s.frames.contains { ($0.knee ?? 0) > 160 && ($0.hip ?? 180) < 120 }
                },
                FormRule(id: "deadlift.squatting", weight: 20) { ($0.min(\.knee) ?? 180) < 95 },
            ])
        case .romanianDeadlift:
            return ExerciseSpec(primary: { $0.hip }, flexed: 140, extended: 160, workFlexed: true,
                required: [\.hip, \.knee], rules: [
                FormRule(id: "rdl.range", weight: 20) { ($0.peakFrame.hip ?? 0) > 115 },
                FormRule(id: "rdl.knees", weight: 35) { ($0.peakFrame.knee ?? 180) < 140 },
                FormRule(id: "tempo.fast", weight: 10) { $0.descent < 0.6 },
            ])
        case .overheadPress:
            return ExerciseSpec(primary: { $0.elbow }, flexed: 100, extended: 140, workFlexed: false,
                required: [\.elbow, \.torsoLean], rules: [
                FormRule(id: "ohp.lockout", weight: 20) { ($0.peakFrame.elbow ?? 180) < 160 },
                FormRule(id: "ohp.lean", weight: 35) { ($0.max(\.torsoLean) ?? 0) > 18 },
            ])
        case .bicepCurl:
            return ExerciseSpec(primary: { $0.elbow }, flexed: 95, extended: 135, workFlexed: true,
                required: [\.elbow, \.elbowDrift, \.torsoLean], rules: [
                FormRule(id: "curl.top", weight: 20) { ($0.peakFrame.elbow ?? 0) > 60 },
                FormRule(id: "curl.bottom", weight: 20) { ($0.max(\.elbow) ?? 180) < 150 },
                FormRule(id: "curl.elbow", weight: 20) { ($0.max(\.elbowDrift) ?? 0) > 0.35 },
                FormRule(id: "curl.swing", weight: 35) { ($0.range(\.torsoLean) ?? 0) > 15 },
            ])
        case .lunge:
            return ExerciseSpec(primary: { $0.frontKnee }, flexed: 130, extended: 150, workFlexed: true,
                required: [\.frontKnee, \.torsoLean], rules: [
                FormRule(id: "lunge.depth", weight: 35) { ($0.peakFrame.frontKnee ?? 0) > 105 },
                FormRule(id: "lunge.torso", weight: 20) { ($0.peakFrame.torsoLean ?? 0) > 25 },
            ])
        case .pushUp:
            return ExerciseSpec(primary: { $0.elbow }, flexed: 128, extended: 152, workFlexed: true,
                required: [\.elbow, \.hipOffset], rules: [
                FormRule(id: "pushup.depth", weight: 35) { ($0.peakFrame.elbow ?? 0) > 100 },
                FormRule(id: "pushup.sag", weight: 20) { $0.share(\.hipOffset) { $0 < -0.08 } > 0.3 },
                FormRule(id: "pushup.pike", weight: 20) { $0.share(\.hipOffset) { $0 > 0.12 } > 0.3 },
                FormRule(id: "pushup.lockout", weight: 10) { ($0.max(\.elbow) ?? 180) < 155 },
            ])
        case .pullUp:
            return ExerciseSpec(primary: { $0.elbow }, flexed: 110, extended: 145, workFlexed: true,
                required: [\.elbow, \.noseOverWrists], rules: [
                FormRule(id: "pullup.chin", weight: 35) { ($0.peakFrame.noseOverWrists ?? 1) < 0 },
                FormRule(id: "pullup.hang", weight: 20) { ($0.max(\.elbow) ?? 180) < 150 },
                FormRule(id: "pullup.kip", weight: 20) { ($0.range(\.hipX) ?? 0) > 0.25 },
            ])
        case .dip:
            return ExerciseSpec(primary: { $0.elbow }, flexed: 120, extended: 150, workFlexed: true,
                required: [\.elbow], rules: [
                FormRule(id: "dip.depth", weight: 35) { ($0.peakFrame.elbow ?? 0) > 95 },
                FormRule(id: "dip.lockout", weight: 10) { ($0.max(\.elbow) ?? 180) < 155 },
            ])
        case .plank:
            return ExerciseSpec(primary: { $0.bodyLine }, flexed: 0, extended: 0, workFlexed: true,
                required: [\.hipOffset, \.bodyLine],
                rules: [
                    FormRule(id: "plank.sag", weight: 35, violated: { _ in false },
                             share: { $0.share(\.hipOffset) { $0 < -0.08 } }),
                    FormRule(id: "plank.pike", weight: 20, violated: { _ in false },
                             share: { $0.share(\.hipOffset) { $0 > 0.12 } }),
                ],
                // Recognised by lying roughly flat, not by how straight the
                // body is — a sagging plank is still a plank, just a bad one.
                inPose: { ($0.bodyTilt ?? 90) < 35 })
        case .warrior2:
            return ExerciseSpec(primary: { $0.frontKnee }, flexed: 0, extended: 0, workFlexed: true,
                required: [\.frontKnee, \.armsLevel, \.torsoLean],
                rules: [
                    FormRule(id: "warrior.knee", weight: 35, violated: { _ in false },
                             share: { $0.share(\.frontKnee) { $0 > 125 } }),
                    FormRule(id: "warrior.arms", weight: 20, violated: { _ in false },
                             share: { $0.share(\.armsLevel) { $0 > 0.2 } }),
                    FormRule(id: "warrior.torso", weight: 20, violated: { _ in false },
                             share: { $0.share(\.torsoLean) { $0 > 15 } }),
                ],
                inPose: { ($0.frontKnee ?? 180) < 150 })
        case .downwardDog:
            return ExerciseSpec(primary: { $0.bodyLine }, flexed: 0, extended: 0, workFlexed: true,
                required: [\.bodyLine, \.elbow, \.knee],
                rules: [
                    FormRule(id: "dog.hips", weight: 35, violated: { _ in false },
                             share: { $0.share(\.bodyLine) { $0 > 110 } }),
                    FormRule(id: "dog.arms", weight: 20, violated: { _ in false },
                             share: { $0.share(\.elbow) { $0 < 150 } }),
                    FormRule(id: "dog.legs", weight: 10, violated: { _ in false },
                             share: { $0.share(\.knee) { $0 < 145 } }),
                ],
                inPose: { ($0.bodyLine ?? 180) < 135 })
        case .treePose:
            return ExerciseSpec(primary: { $0.backKnee }, flexed: 0, extended: 0, workFlexed: true,
                required: [\.backKnee, \.frontKnee, \.torsoLean],
                rules: [
                    FormRule(id: "tree.leg", weight: 20, violated: { _ in false },
                             share: { $0.share(\.backKnee) { $0 < 165 } }),
                    FormRule(id: "tree.torso", weight: 20, violated: { _ in false },
                             share: { $0.share(\.torsoLean) { $0 > 10 } }),
                    // Balance: the hips wander more than a sway.
                    FormRule(id: "tree.balance", weight: 20, violated: { ($0.range(\.hipX) ?? 0) > 0.2 },
                             share: nil),
                ],
                // One foot up: one knee well bent, the other straight.
                inPose: { ($0.frontKnee ?? 180) < 120 && ($0.backKnee ?? 0) > 150 })
        }
    }
}
