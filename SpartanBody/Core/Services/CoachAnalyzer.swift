import Foundation

// MARK: - Inputs

/// Everything the coach reads to build a week.
///
/// A plain value on purpose: the planning rules can be tested with made-up
/// histories, without the app's stores. The live one is built by
/// `CoachInputs.current()` in PlanStore.swift.
struct CoachInputs {
    // Who
    var goal: FitnessGoal
    var activityLevel: ActivityLevel
    var sex: BiologicalSex
    var weightKg: Double
    var heightCm: Double
    var bmi: Double
    var bmiCategory: String
    /// Formula target from the profile, before any coach adjustment.
    var baseCalories: Int
    var protein: Int
    var sportID: String?
    var sportDaysPerWeek: Int
    /// Weekdays of the sport (Calendar: 1 = Sunday … 7 = Saturday). Empty
    /// when the user hasn't picked them — the plan then only knows how many.
    var sportWeekdays: [Int] = []
    var extraContext: String
    /// What the user told Spartan (injuries, home training, diet…). Read
    /// like the notes above, but kept apart so it isn't saved into them.
    var memoryNotes: String = ""
    /// Recipes the user said they don't like; never put in the menu.
    var bannedRecipes: Set<String> = []
    /// The foods themselves ("tofu"), so the plan's text stops naming them.
    var dislikedFoods: [String] = []

    // What they did
    /// Finished gym sessions, newest first.
    var sessions: [WorkoutSession]
    var weighIns: [WeightEntry]
    /// Calories logged on each of the last 7 full days (today excluded,
    /// because a half-logged day would drag the average down).
    var dailyCalories: [Double]
    var currentStreak: Int
    /// Sport sessions (BJJ class, match…) logged in the last 7 days.
    var sportSessionsLast7: Int = 0

    // State carried over from last week's plan
    /// Workout days the plan being replaced asked for. nil on the first plan.
    var previousPlannedSessions: Int?
    /// Week of the 4-week cycle this new plan belongs to.
    var blockWeek: Int
    /// Calorie adjustment accumulated in earlier weeks.
    var calorieAdjustment: Int
    /// False when regenerating within the same week, so pressing "New plan"
    /// twice doesn't cut calories twice.
    var canAdjustCalories: Bool

    var now: Date = .now
    /// Varies meal and exercise picks between weeks without being random
    /// within one (the same inputs always give the same plan).
    var seed: UInt64 = 1
}

// MARK: - Analyzer

/// Reads the user's last weeks and decides how the next one should change.
///
/// Rules, not a model: every decision maps to one line in `CoachReport.notes`
/// so the user can see exactly why their week looks the way it does.
enum CoachAnalyzer {

    struct Decision {
        var report: CoachReport
        var trainingDays: Int
        /// This week's average daily calories, adjustment included.
        var weeklyCalories: Int
        var isBeginner: Bool
        var isDeload: Bool { report.volume == .deload }
    }

    static func analyze(_ i: CoachInputs) -> Decision {
        let day: TimeInterval = 86_400
        let done7  = i.sessions.filter { $0.startedAt >= i.now.addingTimeInterval(-7 * day) }.count
        let done14 = i.sessions.filter { $0.startedAt >= i.now.addingTimeInterval(-14 * day) }.count
        let everTrained = !i.sessions.isEmpty

        var notes: [String] = []

        // ── Training days (before any cut) ──────────────────────────────────
        var baseDays: Int
        switch i.activityLevel {
        case .sedentary, .light: baseDays = 3
        case .moderate:          baseDays = 4
        case .active:            baseDays = 5
        }
        // Sport practice is training too: take gym days away so total load
        // stays recoverable.
        if i.sportDaysPerWeek >= 3 { baseDays -= 1 }
        if i.sportDaysPerWeek >= 5 { baseDays -= 1 }
        baseDays = min(max(baseDays, 2), 5)

        // ── Volume ──────────────────────────────────────────────────────────
        let stalled = stalledLifts(i.sessions, now: i.now)
        let volume: CoachReport.VolumeDecision
        if !everTrained && i.previousPlannedSessions == nil {
            volume = .firstWeek
            notes.append(L("coach.report.firstWeek"))
        } else if everTrained && done14 == 0 {
            volume = .comeback
            notes.append(L("coach.report.comeback"))
        } else if i.blockWeek >= 4 {
            volume = .deload
            notes.append(L("coach.report.deload.block"))
        } else if stalled.count >= 2 {
            volume = .deload
            notes.append(String(format: L("coach.report.deload.stall"), stalled.count))
        } else if i.currentStreak >= 12 {
            volume = .deload
            notes.append(String(format: L("coach.report.deload.streak"), i.currentStreak))
        } else if let planned = i.previousPlannedSessions, planned > 0 {
            let adherence = Double(done7) / Double(planned)
            if adherence < 0.5 {
                volume = .reduced
                // Already at the floor there's no day to take away — say so
                // instead of claiming a cut that didn't happen.
                notes.append(baseDays > 2
                    ? String(format: L("coach.report.adherence.low"), done7, planned)
                    : String(format: L("coach.report.adherence.lowMin"), done7, planned, baseDays))
            } else if adherence >= 0.9 {
                volume = .increased
                notes.append(String(format: L("coach.report.adherence.high"), done7, planned))
            } else {
                volume = .kept
                notes.append(String(format: L("coach.report.adherence.ok"), done7, planned))
            }
        } else {
            volume = .kept
        }

        // Sport practice is load too. Two or more sessions over what the user
        // planned means they're already training more than the plan assumes:
        // don't pile extra gym volume on top.
        var finalVolume = volume
        let plannedSport = i.sportWeekdays.isEmpty ? i.sportDaysPerWeek : i.sportWeekdays.count
        if i.sportID != nil, plannedSport > 0, i.sportSessionsLast7 >= plannedSport + 2,
           volume == .increased {
            finalVolume = .kept
            let name = NSLocalizedString(SportLibrary.byID(i.sportID!)?.nameKey ?? "", comment: "")
            notes.append(String(format: L("coach.report.sportLoad"), i.sportSessionsLast7, name))
        }

        // ── Training days ───────────────────────────────────────────────────
        var days = baseDays
        if finalVolume == .reduced || finalVolume == .comeback { days = max(days - 1, 2) }

        // ── Calories ────────────────────────────────────────────────────────
        let rate = weightRate(i.weighIns, now: i.now)
        let target = targetRate(goal: i.goal, weightKg: i.weightKg)
        let logged = i.dailyCalories.filter { $0 >= 500 }   // a lone coffee isn't a logged day
        let avgCalories = logged.count >= 3 ? Int(logged.reduce(0, +) / Double(logged.count)) : nil
        let currentTarget = i.baseCalories + i.calorieAdjustment

        var change = 0
        if i.canAdjustCalories {
            if let rate {
                if let avg = avgCalories,
                   abs(Double(avg - currentTarget)) / Double(max(currentTarget, 1)) > 0.15 {
                    // Eating far from the target: the target isn't the problem yet.
                    notes.append(String(format: L("coach.report.kcal.offTarget"), avg, currentTarget))
                } else {
                    change = calorieChange(goal: i.goal, rate: rate, target: target)
                    let key = change < 0 ? "coach.report.kcal.down"
                            : change > 0 ? "coach.report.kcal.up"
                            : "coach.report.kcal.onTrack"
                    notes.append(change == 0
                        ? String(format: L(key), kg(rate), kg(target))
                        : String(format: L(key), kg(rate), kg(target), abs(change)))
                }
            } else {
                notes.append(L("coach.report.kcal.noData"))
            }
        } else if i.calorieAdjustment != 0 {
            // Plan rebuilt mid-week: the adjustment stays, so say so — else the
            // lower (or higher) target looks like it came from nowhere.
            notes.append(String(format: L("coach.report.kcal.kept"), i.calorieAdjustment))
        }

        var total = min(max(i.calorieAdjustment + change, -450), 450)
        // Never plan below a safe floor, whatever the adjustments add up to.
        let floor = i.sex == .female ? 1200 : 1500
        if i.baseCalories + total < floor { total = floor - i.baseCalories }
        change = total - i.calorieAdjustment

        let report = CoachReport(
            sessionsDone: done7,
            sessionsPlanned: i.previousPlannedSessions,
            weightRate: rate,
            targetRate: target,
            avgCalories: avgCalories,
            loggedDays: logged.count,
            calorieChange: change,
            calorieAdjustmentTotal: total,
            volume: finalVolume,
            stalledLifts: stalled,
            blockWeek: finalVolume == .deload ? 4 : i.blockWeek,
            notes: notes,
            sportSessions: i.sportID == nil ? nil : i.sportSessionsLast7)

        let beginner = (i.activityLevel == .sedentary || i.activityLevel == .light)
            && i.sessions.count < 12

        return Decision(report: report, trainingDays: days,
                        weeklyCalories: i.baseCalories + total, isBeginner: beginner)
    }

    // MARK: - Weight trend

    /// Least-squares slope of the weigh-ins from the last 21 days, in kg per
    /// week. Needs at least 3 weigh-ins spread over a week — two points are
    /// mostly water and noise.
    static func weightRate(_ entries: [WeightEntry], now: Date) -> Double? {
        let recent = entries.filter { $0.date >= now.addingTimeInterval(-21 * 86_400) }
        guard recent.count >= 3,
              let first = recent.map(\.date).min(),
              let last = recent.map(\.date).max(),
              last.timeIntervalSince(first) >= 7 * 86_400 else { return nil }

        let xs = recent.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = recent.map(\.weightKg)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return (sxy / sxx) * 7
    }

    /// Rate the goal calls for: lose 0.5% of body weight a week, gain 0.25%.
    static func targetRate(goal: FitnessGoal, weightKg: Double) -> Double {
        let raw: Double
        switch goal {
        case .loseWeight: raw = -0.005 * weightKg
        case .gainMuscle: raw =  0.0025 * weightKg
        case .stayFit:    raw = 0
        }
        return (raw / 0.05).rounded() * 0.05
    }

    /// ±150 kcal steps. Small on purpose: a week of weigh-ins is noisy, and a
    /// small step repeated is safer than a big one reversed.
    static func calorieChange(goal: FitnessGoal, rate: Double, target: Double) -> Int {
        switch goal {
        case .loseWeight:
            if rate > target * 0.5 { return -150 }   // losing too slowly, or gaining
            if rate < target * 2   { return  150 }   // losing too fast: protect muscle
        case .gainMuscle:
            if rate < target * 0.5 { return  150 }
            if rate > target * 3   { return -150 }   // mostly fat at that speed
        case .stayFit:
            if rate >  0.25 { return -100 }
            if rate < -0.25 { return  100 }
        }
        return 0
    }

    // MARK: - Stalls

    /// Main lifts where ProgressionEngine would call for a deload: the same
    /// weight twice in a row without hitting the reps.
    static func stalledLifts(_ sessions: [WorkoutSession], now: Date) -> [String] {
        let recent = sessions.filter { $0.startedAt >= now.addingTimeInterval(-28 * 86_400) }
        let mains = ["squat", "bench_press", "deadlift", "overhead_press", "barbell_row",
                     "romanian_deadlift", "hip_thrust", "incline_dumbbell_press"]
        return mains.filter { id in
            guard let last = recent.lazy.compactMap({ $0.exercises.first { $0.exerciseID == id } }).first,
                  let reps = last.sets.first?.reps, reps > 0 else { return false }
            return ProgressionEngine.suggestion(for: id, history: recent, targetReps: reps,
                                                fallbackWeight: 0).reason == .deload
        }
    }

    // MARK: - Helpers

    private static func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    /// "-0.3" style, with the sign always shown.
    private static func kg(_ v: Double) -> String { String(format: "%+.1f", v) }
}
