import Foundation

// MARK: - Model

/// Apple Health values per day, keyed by start of day. Days with no data are
/// absent — most people have no sleep or HRV data without a watch.
struct HealthDailyHistory {
    var steps:      [Date: Double] = [:]
    var sleepHours: [Date: Double] = [:]
    var restingHR:  [Date: Double] = [:]
    var hrv:        [Date: Double] = [:]
}

/// The six things a week is judged on. Order is the tie-break when two score
/// the same: recovery problems come first because they undo everything else.
enum ReviewArea: String, Codable, CaseIterable {
    case recovery, sleep, training, protein, activity, logging

    var labelKey: String { "review.area.\(rawValue)" }
    var icon: String {
        switch self {
        case .recovery: return "heart.text.square.fill"
        case .sleep:    return "moon.zzz.fill"
        case .training: return "dumbbell.fill"
        case .protein:  return "fork.knife"
        case .activity: return "figure.walk"
        case .logging:  return "checklist"
        }
    }
}

/// One calendar week, rebuilt from what the user logged and what Apple Health
/// recorded. Stores numbers only; every sentence is written at display time,
/// so the history follows the app's language.
struct WeeklyReview: Codable, Identifiable, Equatable {
    var id: Date { weekStart }
    var weekStart: Date

    var workoutsDone: Int
    var workoutsPlanned: Int
    var sportSessions: Int
    /// Change across the week, kg. nil without weigh-ins on both sides.
    var weightChange: Double?
    var loggedDays: Int
    var avgCalories: Int?
    var avgProtein: Int?
    var calorieTarget: Int
    var proteinTarget: Int
    var avgSleep: Double?
    var avgSteps: Int?
    var restingHR: Double?
    var restingHRBaseline: Double?
    var hrv: Double?
    var hrvBaseline: Double?

    /// 0–100 per area; areas without data are absent.
    var scores: [String: Int]
    /// The weakest area, or nil when every area scored 80 or more.
    var focus: ReviewArea?
    var score: Int
    /// What the coach decided when it planned this week, if it did.
    var coachNotes: [String]?

    func score(_ a: ReviewArea) -> Int? { scores[a.rawValue] }
}

/// A plan the coach generated, kept so past weeks know what was asked of them
/// and what the coach decided.
struct CoachDecision: Codable {
    var date: Date
    var plannedWorkouts: Int
    var notes: [String]
}

// MARK: - Engine

enum WeeklyReviewEngine {

    struct Inputs {
        var sessions: [WorkoutSession]
        var sportSessionDates: [Date]
        var weighIns: [WeightEntry]
        /// Logged (kcal, protein) per day.
        var food: [Date: (kcal: Double, protein: Double)]
        var health: HealthDailyHistory
        var calorieTarget: Int
        var proteinTarget: Int
        /// Gym days expected when no coach plan covered the week.
        var defaultPlanned: Int
        var decisions: [CoachDecision]
        var now: Date
        var calendar: Calendar = .current
    }

    /// The last `weeks` complete calendar weeks, newest first. Weeks with no
    /// data at all are left out, so a new user doesn't see empty zeros.
    static func build(_ i: Inputs, weeks: Int) -> [WeeklyReview] {
        let cal = i.calendar
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: i.now)?.start else { return [] }
        // Weeks before the user started (first workout, class or logged meal)
        // aren't theirs to be judged on. A weigh-in synced from Health a month
        // before they installed the app would otherwise show as a week scoring 0.
        let firstUse = (i.sessions.map(\.startedAt) + i.sportSessionDates
                        + i.food.filter { $0.value.kcal >= 500 }.map(\.key)).min()
        guard let firstUse else { return [] }
        return (1...weeks).compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = cal.date(byAdding: .day, value: 7, to: start),
                  end > firstUse else { return nil }
            return review(weekStart: start, i)
        }
    }

    static func review(weekStart start: Date, _ i: Inputs) -> WeeklyReview? {
        let cal = i.calendar
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
        func inWeek(_ d: Date) -> Bool { d >= start && d < end }

        // Training
        let done = i.sessions.filter { inWeek($0.startedAt) && $0.finishedAt != nil }.count
        let sport = i.sportSessionDates.filter(inWeek).count
        // The plan that was running mid-week says what was asked.
        let mid = cal.date(byAdding: .day, value: 3, to: start) ?? start
        let decision = i.decisions.filter { $0.date <= mid }.max { $0.date < $1.date }
        let planned = decision?.plannedWorkouts ?? i.defaultPlanned
        let notes = i.decisions.filter { inWeek($0.date) }.max { $0.date < $1.date }?.notes

        // Food: a day counts as logged from 500 kcal — a coffee isn't a day.
        let logged = days.compactMap { i.food[$0] }.filter { $0.kcal >= 500 }
        let avgKcal = logged.count >= 3 ? Int(logged.map(\.kcal).reduce(0, +) / Double(logged.count)) : nil
        let avgProt = logged.count >= 3 ? Int(logged.map(\.protein).reduce(0, +) / Double(logged.count)) : nil

        // Weight: last weigh-in of the week against the last one before it.
        let before = i.weighIns.filter { $0.date < start && $0.date >= start.addingTimeInterval(-10 * 86_400) }
            .max { $0.date < $1.date }
        let within = i.weighIns.filter { inWeek($0.date) }.max { $0.date < $1.date }
        let weightChange = (before != nil && within != nil) ? within!.weightKg - before!.weightKg : nil

        // Health: averages over days that have data.
        func avg(_ m: [Date: Double], _ ds: [Date], min n: Int) -> Double? {
            let v = ds.compactMap { m[$0] }
            return v.count >= n ? v.reduce(0, +) / Double(v.count) : nil
        }
        let sleep = avg(i.health.sleepHours, days, min: 3)
        let steps = avg(i.health.steps, days, min: 3).map { Int($0) }
        let rhr = avg(i.health.restingHR, days, min: 3)
        let hrv = avg(i.health.hrv, days, min: 3)
        // Baseline: the three weeks before — your own normal, not a textbook one.
        let baseDays = (1...21).compactMap { cal.date(byAdding: .day, value: -$0, to: start) }
        let rhrBase = avg(i.health.restingHR, baseDays, min: 7)
        let hrvBase = avg(i.health.hrv, baseDays, min: 7)

        let anyData = done + sport > 0 || !logged.isEmpty || within != nil
            || sleep != nil || steps != nil
        guard anyData else { return nil }

        // Scores
        var s: [ReviewArea: Int] = [:]
        s[.logging] = Int(Double(logged.count) / 7 * 100)
        if planned > 0 { s[.training] = pct(Double(done) / Double(planned)) }
        if let avgProt { s[.protein] = pct(Double(avgProt) / Double(max(i.proteinTarget, 1))) }
        if let sleep { s[.sleep] = pct((sleep - 5) / 2.5) }              // 5 h → 0, 7.5 h → 100
        if let steps { s[.activity] = pct(Double(steps) / 8000) }
        if let rhr, let hrv, let rhrBase, let hrvBase {
            var r = 100
            let hrvDrop = (hrvBase - hrv) / hrvBase
            if hrvDrop > 0.10 { r -= 45 } else if hrvDrop > 0.05 { r -= 20 }
            let rhrUp = rhr - rhrBase
            if rhrUp >= 5 { r -= 45 } else if rhrUp >= 3 { r -= 20 }
            s[.recovery] = max(r, 0)
        }

        let focus = ReviewArea.allCases
            .compactMap { a in s[a].map { (a, $0) } }
            .filter { $0.1 < 80 }
            .min { $0.1 < $1.1 }?.0
        let overall = s.isEmpty ? 0 : s.values.reduce(0, +) / s.count

        return WeeklyReview(
            weekStart: start, workoutsDone: done, workoutsPlanned: planned, sportSessions: sport,
            weightChange: weightChange, loggedDays: logged.count,
            avgCalories: avgKcal, avgProtein: avgProt,
            calorieTarget: i.calorieTarget, proteinTarget: i.proteinTarget,
            avgSleep: sleep, avgSteps: steps,
            restingHR: rhr, restingHRBaseline: rhrBase, hrv: hrv, hrvBaseline: hrvBase,
            scores: Dictionary(uniqueKeysWithValues: s.map { ($0.key.rawValue, $0.value) }),
            focus: focus, score: overall, coachNotes: notes)
    }

    private static func pct(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 100).rounded()) }

    // MARK: - Words

    /// The one thing to work on next week, with the numbers that justify it.
    static func focusText(_ r: WeeklyReview) -> String {
        func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        guard let focus = r.focus else { return L("review.focus.none") }
        switch focus {
        case .recovery:
            let rhrUp = Int(((r.restingHR ?? 0) - (r.restingHRBaseline ?? 0)).rounded())
            let hrvDrop = Int((((r.hrvBaseline ?? 1) - (r.hrv ?? 0)) / (r.hrvBaseline ?? 1) * 100).rounded())
            return String(format: L("review.focus.recovery"), max(rhrUp, 0), max(hrvDrop, 0))
        case .sleep:
            let h = r.avgSleep ?? 0
            return String(format: L("review.focus.sleep"), Int(h), Int((h - Double(Int(h))) * 60))
        case .training:
            return String(format: L("review.focus.training"), r.workoutsDone, r.workoutsPlanned)
        case .protein:
            return String(format: L("review.focus.protein"), r.avgProtein ?? 0, r.proteinTarget)
        case .activity:
            return String(format: L("review.focus.activity"), r.avgSteps ?? 0)
        case .logging:
            return String(format: L("review.focus.logging"), r.loggedDays)
        }
    }
}
