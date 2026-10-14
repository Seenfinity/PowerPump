import Foundation

/// On-device progressive-overload engine.
///
/// Reads what the user actually lifted (WorkoutStore history) and decides the
/// weight for the next session of each exercise. No network, no model file —
/// deterministic rules that mirror how a coach programs linear progression:
///
///   • Completed every set at the target reps  → add a small increment
///   • Missed some reps                        → repeat the same weight
///   • Stalled twice in a row                  → deload ~10% and climb back
///
/// The rules are per-exercise-size: a barbell squat jumps 5 kg, a lateral
/// raise 1 kg, because the same absolute jump is trivial on one and impossible
/// on the other.
struct ProgressionEngine {

    // MARK: - Public API

    /// What the engine decided for one exercise.
    struct Suggestion {
        let exerciseID: String
        /// Weight to use next session, in kg. 0 for bodyweight movements.
        let weight: Double
        /// Reps to aim for.
        let reps: Int
        let reason: Reason

        enum Reason {
            case firstTime          // no history yet — conservative start
            case progressed         // hit all reps, adding weight
            case hold               // missed reps, repeat the same load
            case deload             // stalled repeatedly, backing off
        }
    }

    /// Suggests the next working weight for `exerciseID`.
    ///
    /// - Parameters:
    ///   - history: completed sessions, newest first (WorkoutStore.history).
    ///   - targetReps: the rep target of the programmed set.
    ///   - fallbackWeight: weight used when the user has no history at all.
    static func suggestion(for exerciseID: String,
                           history: [WorkoutSession],
                           targetReps: Int,
                           fallbackWeight: Double) -> Suggestion {

        let sessions = recentSessions(of: exerciseID, in: history, limit: 3)

        // No history: start from the template's weight so the user still gets a
        // sensible number, and let the next sessions calibrate it.
        guard let last = sessions.first else {
            return Suggestion(exerciseID: exerciseID, weight: fallbackWeight,
                              reps: targetReps, reason: .firstTime)
        }

        let lastWeight = workingWeight(of: last)
        let step = increment(forExerciseID: exerciseID, weight: lastWeight)

        // Stalled twice at the same weight → deload to break the plateau.
        if sessions.count >= 2, isStalled(sessions, targetReps: targetReps) {
            let deloaded = round(toStep: lastWeight * 0.9, step: step)
            return Suggestion(exerciseID: exerciseID, weight: max(0, deloaded),
                              reps: targetReps, reason: .deload)
        }

        // How hard the last session felt, if the user told Spartan.
        let lastRPE = history.first { $0.exercises.contains { $0.exerciseID == exerciseID } }?.rpe

        // Completed every programmed set at target reps → add weight.
        if hitAllReps(last, targetReps: targetReps) {
            // All reps done but it was at the limit: repeat until it feels
            // manageable, instead of piling weight on a grinding lift.
            if let rpe = lastRPE, rpe >= 9 {
                return Suggestion(exerciseID: exerciseID, weight: lastWeight,
                                  reps: targetReps, reason: .hold)
            }
            // Bodyweight movements have no load to add: progress via reps instead.
            guard lastWeight > 0 else {
                return Suggestion(exerciseID: exerciseID, weight: 0,
                                  reps: targetReps + 1, reason: .progressed)
            }
            // Easy (RPE 6 or less): a bigger jump.
            let jump = (lastRPE ?? 7) <= 6 ? step * 2 : step
            return Suggestion(exerciseID: exerciseID, weight: lastWeight + jump,
                              reps: targetReps, reason: .progressed)
        }

        // Missed reps → stay at the same weight until it's clean.
        return Suggestion(exerciseID: exerciseID, weight: lastWeight,
                          reps: targetReps, reason: .hold)
    }

    // MARK: - History reading

    /// The user's last `limit` sessions that included this exercise, newest first.
    private static func recentSessions(of exerciseID: String,
                                       in history: [WorkoutSession],
                                       limit: Int) -> [SessionExercise] {
        history
            .compactMap { session in
                session.exercises.first { $0.exerciseID == exerciseID }
            }
            .filter { $0.sets.contains(where: \.completed) }
            .prefix(limit)
            .map { $0 }
    }

    /// The heaviest weight the user actually completed in that session — the
    /// working set, ignoring lighter warm-up sets.
    private static func workingWeight(of exercise: SessionExercise) -> Double {
        exercise.sets.filter(\.completed).map(\.weight).max() ?? 0
    }

    /// True when every completed set reached the rep target.
    private static func hitAllReps(_ exercise: SessionExercise, targetReps: Int) -> Bool {
        let done = exercise.sets.filter(\.completed)
        guard !done.isEmpty else { return false }
        // Require the user to have finished the programmed sets, not just one.
        guard done.count >= exercise.sets.count else { return false }
        return done.allSatisfy { $0.reps >= targetReps }
    }

    /// Two sessions in a row at the same weight without hitting the reps.
    private static func isStalled(_ sessions: [SessionExercise], targetReps: Int) -> Bool {
        let recent = sessions.prefix(2)
        guard recent.count == 2 else { return false }
        let weights = recent.map { workingWeight(of: $0) }
        guard let first = weights.first, weights.allSatisfy({ $0 == first }) else { return false }
        return recent.allSatisfy { !hitAllReps($0, targetReps: targetReps) }
    }

    // MARK: - Increments

    /// How much to add, based on how much load the movement already carries.
    /// Big compound lifts tolerate bigger jumps than small isolation work.
    private static func increment(forExerciseID id: String, weight: Double) -> Double {
        if heavyCompounds.contains(id) { return weight >= 60 ? 5.0 : 2.5 }
        if isolationLifts.contains(id) { return 1.0 }
        return 2.5
    }

    private static func round(toStep value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Lifts that use a barbell and the whole body — 5 kg jumps are realistic.
    private static let heavyCompounds: Set<String> = [
        "squat", "back_squat", "deadlift", "romanian_deadlift",
        "bench_press", "barbell_row", "overhead_press", "hip_thrust",
        "barbell_hip_thrust", "clean_and_press", "front_squat", "leg_press",
    ]

    /// Small single-joint movements — 1 kg is already a real jump.
    private static let isolationLifts: Set<String> = [
        "lateral_raise", "hammer_curl", "barbell_curl", "skull_crusher",
        "cable_fly", "face_pull", "calf_raise", "wrist_curl", "tricep_pushdown",
        "preacher_curl", "rear_delt_fly",
    ]
}
