import Foundation

// Every field added after v1 is Optional: plans are persisted as JSON, and a
// synthesized decoder only tolerates a missing key for Optional properties.
// A non-optional field — even one with a default value — would make every
// plan saved by an older build fail to load.

struct FitnessPlan: Codable {
    var analysis:       String
    var weeklySchedule: [DayPlan]
    var nutritionPlan:  AINutritionPlan
    var tips:           [String]
    var motivation:     String
    var weeklyMeals:    [DayMeals] = []
    /// What the coach read from the user's last week and what it changed.
    var report:         CoachReport? = nil
}

/// How hard a day is. Drives rep ranges, loads and that day's carbohydrates.
enum DayIntensity: String, Codable, CaseIterable {
    case heavy, medium, light, deload, rest
    /// A day of the user's own sport (BJJ class, football match…) with no gym.
    case sport

    /// Localization key for the badge ("Heavy", "Medium", …).
    var labelKey: String { "coach.intensity.\(rawValue)" }
}

// Suggested menu for one day (recipe names — localized at render time).
struct DayMeals: Codable, Identifiable {
    var id: String { day }
    var day:       String
    var breakfast: String
    var lunch:     String
    var dinner:    String
    /// Full menu with portions. nil on plans saved before portions existed.
    var meals:     [PlannedMeal]? = nil
    var intensity: DayIntensity? = nil
    /// The day's targets, which vary with training load (carb cycling).
    var target:    MacroTarget? = nil

    /// What the planned meals actually add up to.
    var totals: MacroTarget? {
        guard let meals, !meals.isEmpty else { return nil }
        return MacroTarget(kcal:    meals.reduce(0) { $0 + $1.kcal },
                           protein: meals.reduce(0) { $0 + $1.protein },
                           carbs:   meals.reduce(0) { $0 + $1.carbs },
                           fat:     meals.reduce(0) { $0 + $1.fat })
    }
}

struct MacroTarget: Codable, Hashable {
    var kcal:    Int
    var protein: Int
    var carbs:   Int
    var fat:     Int
}

/// One meal of the day: a recipe at some number of servings, or a small
/// combination of foods for snacks.
struct PlannedMeal: Codable, Identifiable, Hashable {
    var id: String { slot.rawValue + name }
    var slot:     MealSlot
    /// English key — recipe or food names are localized at render time.
    var name:     String
    var recipeID: String?
    /// Servings of the recipe (0.75, 1, 1.25 …). nil for food combinations.
    var servings: Double?
    /// Food components with grams, for snacks and plant-based breakfasts.
    var items:    [PlannedFood]?
    var kcal:     Int
    var protein:  Int
    var carbs:    Int
    var fat:      Int

    enum MealSlot: String, Codable, CaseIterable {
        case breakfast, lunch, snack, dinner
        var labelKey: String { "coach.meal.\(rawValue)" }
    }
}

struct PlannedFood: Codable, Hashable {
    var foodID: String
    var name:   String   // English key
    var grams:  Int
}

struct DayPlan: Codable, Identifiable {
    var id: String { day }
    var day:       String   // "Monday", "Tuesday", …
    var type:      String   // "workout" | "rest"
    var focus:     String   // "Chest & Triceps", "Active Recovery", …
    var exercises: [String] // ["Bench Press 4×8", "Push-ups 3×15", …]
    var intensity: DayIntensity? = nil
    /// SportActivity id when the user practises their sport this day — alone
    /// (type "sport") or on top of a short gym session.
    var sport: String? = nil

    var isWorkout: Bool { type.lowercased() == "workout" }
    var isSportDay: Bool { sport != nil }
}

struct AINutritionPlan: Codable {
    var calories: Int
    var protein:  Int
    var carbs:    Int
    var fat:      Int
    var tips:     [String]
}

// MARK: - Coach report

/// The numbers the coach looked at and the decisions it took from them, kept
/// on the plan so the user can see *why* this week looks the way it does.
struct CoachReport: Codable {
    /// Gym sessions finished in the last 7 days.
    var sessionsDone: Int
    /// Sessions the previous plan asked for; nil on the first plan.
    var sessionsPlanned: Int?
    /// Measured weight change, kg per week. nil without enough weigh-ins.
    var weightRate: Double?
    /// What the goal calls for, kg per week (negative = losing).
    var targetRate: Double
    /// Average logged intake on days with logs; nil with fewer than 3 days.
    var avgCalories: Int?
    var loggedDays: Int
    /// Change applied to calories this week, and the running total.
    var calorieChange: Int
    var calorieAdjustmentTotal: Int
    var volume: VolumeDecision
    /// Exercise library ids the user has stalled on.
    var stalledLifts: [String]
    /// Position in the 4-week cycle (4 = deload).
    var blockWeek: Int
    /// Localized sentences explaining each decision, in order.
    var notes: [String]
    /// Sport sessions logged in the last 7 days. nil on older plans.
    var sportSessions: Int? = nil

    var adherence: Double? {
        guard let planned = sessionsPlanned, planned > 0 else { return nil }
        return min(Double(sessionsDone) / Double(planned), 1.5)
    }

    enum VolumeDecision: String, Codable {
        case firstWeek, reduced, kept, increased, deload, comeback
    }
}
