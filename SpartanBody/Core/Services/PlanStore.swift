import Foundation
import Combine

/// Holds the user's current coach plan and keeps it on disk.
///
/// The plan is generated right after onboarding, persists across launches and
/// is rebuilt once a week (`regenerateIfStale`) from what the user actually
/// did, so the coach's analysis has something to act on.
@MainActor
final class PlanStore: ObservableObject {
    static let shared = PlanStore()

    /// The plan the user is currently following. nil until it's generated.
    @Published private(set) var plan: FitnessPlan? { didSet { save() } }

    /// When the current plan was built — day 0 of its week.
    @Published private(set) var generatedAt: Date? { didSet { save() } }

    /// True once the user has been shown the plan for the first time. Lets the
    /// app reveal it right after the tutorial and never interrupt again.
    @Published var hasSeenFirstPlan: Bool {
        didSet { UserDefaults.standard.set(hasSeenFirstPlan, forKey: seenKey) }
    }

    /// What the user typed in "anything else to consider?" (a bad knee,
    /// training at home…). Kept so the weekly automatic plan respects it too.
    private(set) var extraContext: String {
        didSet { UserDefaults.standard.set(extraContext, forKey: contextKey) }
    }

    private let planKey    = "sb_current_plan"
    private let dateKey    = "sb_plan_generated_at"
    private let seenKey    = "sb_seen_first_plan"
    private let contextKey = "sb_plan_extra_context"

    private init() {
        // Read everything before assigning anything. Assigning `plan` runs its
        // didSet, and save() then writes the still-empty `generatedAt` —
        // deleting the stored date before it was read. Every launch then
        // looked like a new week: the cycle advanced and calories were cut
        // again, launch after launch.
        let defaults = UserDefaults.standard
        let savedPlan = defaults.data(forKey: planKey)
            .flatMap { try? JSONDecoder().decode(FitnessPlan.self, from: $0) }
        let savedDate = defaults.object(forKey: dateKey) as? Date
        hasSeenFirstPlan = defaults.bool(forKey: seenKey)
        extraContext = defaults.string(forKey: contextKey) ?? ""
        generatedAt = savedDate
        plan = savedPlan
    }

    // MARK: - Today

    /// Which day of the plan today is.
    ///
    /// The schedule is built starting on the day it was generated — `d[0]` is
    /// generation day — so we count days elapsed rather than matching weekday
    /// names, which are already localised inside the plan and would never match
    /// once the user switches language.
    var todayIndex: Int? {
        guard let plan, !plan.weeklySchedule.isEmpty, let generatedAt else { return nil }
        guard let elapsed = daysSince(generatedAt), elapsed >= 0 else { return nil }
        return elapsed % plan.weeklySchedule.count
    }

    /// The plan's day for any date, counted from generation day like today's.
    func dayPlan(on date: Date) -> DayPlan? {
        guard let plan, !plan.weeklySchedule.isEmpty, let generatedAt else { return nil }
        let cal = Calendar.current
        guard let n = cal.dateComponents([.day], from: cal.startOfDay(for: generatedAt),
                                         to: cal.startOfDay(for: date)).day, n >= 0 else { return nil }
        return plan.weeklySchedule[n % plan.weeklySchedule.count]
    }

    /// The day of the plan the user is on right now, if there is a plan.
    var todayPlan: DayPlan? {
        guard let plan, let i = todayIndex else { return nil }
        return plan.weeklySchedule[i]
    }

    /// Today's menu, and with it today's calorie and macro targets — which
    /// differ from the weekly average because they follow the training load.
    var todayMeals: DayMeals? {
        guard let plan, let i = todayIndex, i < plan.weeklyMeals.count else { return nil }
        return plan.weeklyMeals[i]
    }

    var todayTarget: MacroTarget? { todayMeals?.target }

    /// What to eat today: the plan's targets (they follow the day's training),
    /// or the profile's with the default split when there's no plan yet.
    /// Every screen that shows "today's goal" reads this, so the dashboard,
    /// the food log and the coach's menu never disagree.
    func todayTargets(for profile: UserProfile) -> MacroTarget {
        if let t = todayTarget { return t }
        let kcal = profile.dailyCalorieTarget
        return MacroTarget(kcal: kcal, protein: profile.dailyProteinTarget,
                           carbs: Int(Double(kcal) * 0.45 / 4), fat: Int(Double(kcal) * 0.25 / 9))
    }

    /// The targets for any day: the plan's if the plan covers that day,
    /// otherwise the profile's. Used to judge days that are already over.
    func targets(on date: Date, for profile: UserProfile) -> MacroTarget {
        let cal = Calendar.current
        if let plan, let generatedAt, !plan.weeklyMeals.isEmpty,
           let d = cal.dateComponents([.day], from: cal.startOfDay(for: generatedAt),
                                      to: cal.startOfDay(for: date)).day, d >= 0, d < 7,
           let t = plan.weeklyMeals[d % plan.weeklyMeals.count].target {
            return t
        }
        if cal.isDateInToday(date) { return todayTargets(for: profile) }
        let kcal = profile.dailyCalorieTarget
        return MacroTarget(kcal: kcal, protein: profile.dailyProteinTarget,
                           carbs: Int(Double(kcal) * 0.45 / 4), fat: Int(Double(kcal) * 0.25 / 9))
    }

    // MARK: - Weekly cycle

    /// A week has passed since the plan was built: time to read the new
    /// history and plan the next one.
    var isStale: Bool {
        guard plan != nil else { return false }
        guard let generatedAt, let d = daysSince(generatedAt) else { return true }
        return d >= 7
    }

    /// Rebuilds the plan when its week is over. Called when the app shows the
    /// dashboard; without it the first week would repeat forever.
    func regenerateIfStale() {
        guard isStale, UserProfile.shared.onboardingDone else { return }
        generate(inputs: .current())
    }

    // MARK: - Generation

    /// Builds a plan from the user's profile and history, and stores it. Safe
    /// to call repeatedly — it simply replaces the plan.
    func generate(inputs: CoachInputs) {
        extraContext = inputs.extraContext
        let newPlan = LocalCoachService.generatePlan(inputs)
        plan = newPlan
        generatedAt = .now
        // What the coach decided can't be rebuilt later — keep it for the
        // weekly history.
        CoachHistoryStore.shared.record(newPlan)
        // The widget and the watch show today's targets, which just changed.
        PhoneConnectivityManager.shared.syncToWatch()
    }

    func clear() {
        plan = nil
        generatedAt = nil
    }

    // MARK: - Edits from Spartan

    private func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }

    /// Today's workout cut to its first exercises (they're the compound
    /// ones), for "I only have 30 minutes".
    @discardableResult
    func shortenToday(to count: Int = 3) -> Bool {
        guard var p = plan, let i = todayIndex, p.weeklySchedule[i].isWorkout,
              p.weeklySchedule[i].exercises.count > count else { return false }
        p.weeklySchedule[i].exercises = Array(p.weeklySchedule[i].exercises.prefix(count))
        plan = p
        return true
    }

    /// Today becomes active recovery, for "I'm exhausted".
    @discardableResult
    func easeToday() -> Bool {
        guard var p = plan, let i = todayIndex, p.weeklySchedule[i].isWorkout else { return false }
        p.weeklySchedule[i].type = "rest"
        p.weeklySchedule[i].focus = L("coach.focus.activeRecovery")
        p.weeklySchedule[i].exercises = []
        p.weeklySchedule[i].intensity = .rest
        if i < p.weeklyMeals.count { p.weeklyMeals[i].intensity = .rest }
        plan = p
        return true
    }

    /// Rest days later this week that today's workout can swap with.
    func movableDays() -> [(index: Int, name: String)] {
        guard let p = plan, let today = todayIndex, p.weeklySchedule[today].isWorkout else { return [] }
        return p.weeklySchedule.indices.filter { $0 > today }.compactMap { i in
            let d = p.weeklySchedule[i]
            return !d.isWorkout && !d.isSportDay ? (i, d.day) : nil
        }
    }

    /// Swaps today's workout with a later rest day. Day names stay where they
    /// are; the training and that day's menu (its calories follow the
    /// training) move together.
    @discardableResult
    func moveToday(to target: Int) -> Bool {
        guard var p = plan, let i = todayIndex, p.weeklySchedule.indices.contains(target), target != i else {
            return false
        }
        var a = p.weeklySchedule[i], b = p.weeklySchedule[target]
        (a.day, b.day) = (b.day, a.day)
        p.weeklySchedule[i] = b
        p.weeklySchedule[target] = a
        if p.weeklyMeals.indices.contains(i), p.weeklyMeals.indices.contains(target) {
            var ma = p.weeklyMeals[i], mb = p.weeklyMeals[target]
            (ma.day, mb.day) = (mb.day, ma.day)
            p.weeklyMeals[i] = mb
            p.weeklyMeals[target] = ma
        }
        plan = p
        return true
    }

    /// A different dish for one of today's meals. Returns the new meal.
    @discardableResult
    func swapTodayMeal(_ slot: PlannedMeal.MealSlot) -> PlannedMeal? {
        guard var p = plan, let i = todayIndex, i < p.weeklyMeals.count,
              var meals = p.weeklyMeals[i].meals,
              let m = meals.firstIndex(where: { $0.slot == slot }) else { return nil }
        let plantBased = ["vegan", "vegano", "vegana", "végétal", "vegetarian", "vegetariano"]
            .contains { (extraContext + " " + SpartanMemory.shared.planNotes).lowercased().contains($0) }
        guard let new = DietPlanner.alternative(to: meals[m], goal: UserProfile.shared.goal,
                                                plantBased: plantBased,
                                                banned: SpartanMemory.shared.bannedRecipeIDs,
                                                seed: UInt64(Date().timeIntervalSince1970)) else { return nil }
        meals[m] = new
        p.weeklyMeals[i].meals = meals
        switch slot {
        case .breakfast: p.weeklyMeals[i].breakfast = new.name
        case .lunch:     p.weeklyMeals[i].lunch = new.name
        case .dinner:    p.weeklyMeals[i].dinner = new.name
        default: break
        }
        plan = p
        return new
    }

    /// Rebuilds this week's plan with what Spartan has learned (an injury,
    /// training at home…). Mid-week, so the cycle and calories stay put.
    func rebuildForMemory() {
        guard plan != nil else { return }
        generate(inputs: .current())
    }

    /// What carries over from the plan being replaced into the next one.
    struct CarryOver {
        var previousPlannedSessions: Int?
        var blockWeek: Int
        var calorieAdjustment: Int
        var canAdjustCalories: Bool
    }

    /// Reads the current plan before it's replaced. A plan at least 6 days old
    /// counts as last week's: its workouts become the adherence baseline and
    /// the 4-week cycle moves on. A younger one (the user pressed "New plan"
    /// mid-week) keeps its week, and calories aren't adjusted twice.
    func carryOver() -> CarryOver {
        guard let plan, let report = plan.report else {
            // First plan, or one saved before the coach kept a report.
            return CarryOver(previousPlannedSessions: plan.map { p in p.weeklySchedule.filter(\.isWorkout).count },
                             blockWeek: 1, calorieAdjustment: 0, canAdjustCalories: plan != nil)
        }
        let age = generatedAt.flatMap(daysSince) ?? 7
        guard age >= 6 else {
            // Keep this week's adjustment as it is — no new one on top.
            return CarryOver(previousPlannedSessions: report.sessionsPlanned,
                             blockWeek: report.blockWeek,
                             calorieAdjustment: report.calorieAdjustmentTotal,
                             canAdjustCalories: false)
        }
        let nextWeek = (report.volume == .deload || report.blockWeek >= 4) ? 1 : report.blockWeek + 1
        return CarryOver(previousPlannedSessions: plan.weeklySchedule.filter(\.isWorkout).count,
                         blockWeek: nextWeek,
                         calorieAdjustment: report.calorieAdjustmentTotal,
                         canAdjustCalories: true)
    }

    private func daysSince(_ date: Date) -> Int? {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: .now)).day
    }

    // MARK: - Persistence

    private func save() {
        if let plan, let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: planKey)
        } else if plan == nil {
            UserDefaults.standard.removeObject(forKey: planKey)
        }
        UserDefaults.standard.set(generatedAt, forKey: dateKey)
    }
}

// MARK: - Live inputs

extension CoachInputs {
    /// Everything the coach needs, read from the app's stores.
    ///
    /// The single place plans get their data. Before, the plan built after
    /// onboarding passed weight trend and calories as zero, and only the
    /// coach screen's "New plan" read the real numbers.
    @MainActor
    static func current(extraContext: String? = nil) -> CoachInputs {
        let profile = UserProfile.shared
        let store = PlanStore.shared
        let carry = store.carryOver()

        // Last 7 *full* days: today is still being logged.
        let calories = Array(FoodLogStore.shared.dailyCalories(lastDays: 8).dropLast()).map(\.calories)

        return CoachInputs(
            goal: profile.goal,
            activityLevel: profile.activityLevel,
            sex: profile.sex,
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
            bmi: profile.bmi,
            bmiCategory: profile.bmiCategory,
            baseCalories: profile.rawCalorieTarget,
            protein: profile.dailyProteinTarget,
            sportID: profile.practicedSportID,
            sportDaysPerWeek: profile.sportDaysPerWeek,
            sportWeekdays: profile.sportWeekdays,
            extraContext: extraContext ?? store.extraContext,
            memoryNotes: SpartanMemory.shared.planNotes,
            bannedRecipes: SpartanMemory.shared.bannedRecipeIDs,
            dislikedFoods: SpartanMemory.shared.facts.compactMap(\.item),
            sessions: WorkoutStore.shared.history.filter { $0.finishedAt != nil },
            weighIns: ProgressStore.shared.entries(days: 28),
            dailyCalories: calories,
            currentStreak: WorkoutStore.shared.currentStreak,
            sportSessionsLast7: SportSessionStore.shared.history.filter {
                profile.practicedSportIDs.contains($0.sportId)
                    && $0.startedAt >= Date().addingTimeInterval(-7 * 86_400)
            }.count,
            previousPlannedSessions: carry.previousPlannedSessions,
            blockWeek: carry.blockWeek,
            calorieAdjustment: carry.calorieAdjustment,
            canAdjustCalories: carry.canAdjustCalories,
            now: .now,
            // A new seed each day rotates meals and picks between regenerations.
            seed: UInt64(max(0, Int(Date().timeIntervalSince1970 / 86_400))))
    }
}
