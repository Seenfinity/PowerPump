import Foundation
import Combine

/// The coach's week-by-week history for the Profile.
///
/// Reviews are rebuilt from the logs every time rather than frozen when a
/// week ends: food logged late, a weigh-in added afterwards or Health data
/// that syncs from the watch a day later all still count. The one thing that
/// can't be rebuilt — what the coach decided — is recorded as it happens.
@MainActor
final class CoachHistoryStore: ObservableObject {
    static let shared = CoachHistoryStore()

    /// Complete weeks, newest first.
    @Published private(set) var reviews: [WeeklyReview] = []

    private(set) var decisions: [CoachDecision] = [] { didSet { saveDecisions() } }

    private let decisionsKey = "sb_coach_decisions"
    private let reviewsKey   = "sb_coach_reviews"

    private init() {
        let d = UserDefaults.standard
        decisions = d.data(forKey: decisionsKey)
            .flatMap { try? JSONDecoder().decode([CoachDecision].self, from: $0) } ?? []
        // Last computed reviews, shown instantly while Health is re-read.
        reviews = d.data(forKey: reviewsKey)
            .flatMap { try? JSONDecoder().decode([WeeklyReview].self, from: $0) } ?? []
    }

    /// Called by PlanStore for every plan it builds.
    func record(_ plan: FitnessPlan, at date: Date = .now) {
        let entry = CoachDecision(date: date,
                                  plannedWorkouts: plan.weeklySchedule.filter(\.isWorkout).count,
                                  notes: plan.report?.notes ?? [])
        // A plan rebuilt the same day replaces that day's record.
        decisions.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
        decisions.append(entry)
        // A year of weekly decisions is plenty.
        if decisions.count > 60 { decisions.removeFirst(decisions.count - 60) }
    }

    /// Re-reads Apple Health and rebuilds the last 8 weeks.
    func refresh() {
        let health = HealthKitService.shared
        guard health.isAvailable, health.isAuthorized else {
            rebuild(with: HealthDailyHistory())
            return
        }
        // 8 weeks plus 3 weeks of baseline for resting HR and HRV.
        health.fetchDailyHistory(days: 7 * 11 + 7) { [weak self] history in
            self?.rebuild(with: history)
        }
    }

    private func rebuild(with health: HealthDailyHistory) {
        let profile = UserProfile.shared
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        var food: [Date: (kcal: Double, protein: Double)] = [:]
        for back in 0..<(7 * 9 + 7) {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let m = FoodLogStore.shared.macros(for: day)
            if m.calories > 0 { food[day] = (m.calories, m.protein) }
        }

        var planned: Int
        switch profile.activityLevel {
        case .sedentary, .light: planned = 3
        case .moderate:          planned = 4
        case .active:            planned = 5
        }
        if profile.sportDaysPerWeek >= 3 { planned -= 1 }

        let inputs = WeeklyReviewEngine.Inputs(
            sessions: WorkoutStore.shared.history,
            sportSessionDates: SportSessionStore.shared.history
                .filter { profile.practicedSportIDs.contains($0.sportId) }.map(\.startedAt),
            weighIns: ProgressStore.shared.weightEntries,
            food: food,
            health: health,
            calorieTarget: profile.dailyCalorieTarget,
            proteinTarget: profile.dailyProteinTarget,
            defaultPlanned: max(planned, 2),
            decisions: decisions,
            now: .now)
        reviews = WeeklyReviewEngine.build(inputs, weeks: 8)
        if let data = try? JSONEncoder().encode(reviews) {
            UserDefaults.standard.set(data, forKey: reviewsKey)
        }
    }

    private func saveDecisions() {
        if let data = try? JSONEncoder().encode(decisions) {
            UserDefaults.standard.set(data, forKey: decisionsKey)
        }
    }
}
