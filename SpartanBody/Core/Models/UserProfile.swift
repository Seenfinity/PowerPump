import Foundation
import Combine

enum FitnessGoal: String, CaseIterable, Codable {
    case loseWeight  = "Lose Weight"
    case gainMuscle  = "Gain Muscle"
    case stayFit     = "Stay Fit"

    var icon: String {
        switch self {
        case .loseWeight: return "flame.fill"
        case .gainMuscle: return "bolt.fill"
        case .stayFit:    return "heart.fill"
        }
    }

    var description: String {
        switch self {
        case .loseWeight: return "Burn fat with cardio & calorie deficit"
        case .gainMuscle: return "Build strength with progressive overload"
        case .stayFit:    return "Maintain health & energy levels"
        }
    }

    var dailyCalorieAdjustment: Int {
        switch self {
        case .loseWeight: return -500
        case .gainMuscle: return +300
        case .stayFit:    return 0
        }
    }
}

enum BiologicalSex: String, CaseIterable, Codable {
    case male   = "Male"
    case female = "Female"

    var icon: String {
        switch self {
        case .male:   return "figure.stand"
        case .female: return "figure.stand.dress"
        }
    }

    // Mifflin-St Jeor constant: +5 for males, −161 for females.
    var bmrConstant: Double {
        switch self {
        case .male:   return 5
        case .female: return -161
        }
    }
}

enum ActivityLevel: String, CaseIterable, Codable {
    case sedentary   = "Sedentary"
    case light       = "Lightly Active"
    case moderate    = "Moderately Active"
    case active      = "Very Active"

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light:     return 1.375
        case .moderate:  return 1.55
        case .active:    return 1.725
        }
    }
}

@MainActor
final class UserProfile: ObservableObject {
    static let shared = UserProfile()

    @Published var name: String        { didSet { save() } }
    @Published var age: Int            { didSet { save() } }
    @Published var sex: BiologicalSex  { didSet { save() } }
    @Published var weightKg: Double    { didSet { save() } }
    @Published var targetWeightKg: Double { didSet { save() } }
    @Published var heightCm: Double    { didSet { save() } }
    @Published var goal: FitnessGoal   { didSet { save() } }
    @Published var activityLevel: ActivityLevel { didSet { save() } }
    /// SportActivity.ids of the sports the user practices outside the gym
    /// (empty = gym only). Set during onboarding, editable in Profile.
    @Published var practicedSportIDs: [String] { didSet { save() } }
    /// Total practice days per week across all sports (0 when no sport).
    @Published var sportDaysPerWeek: Int { didSet { save() } }
    /// Weekdays the user practises their sport (Calendar weekday: 1 = Sunday
    /// … 7 = Saturday). Empty = not set; the plan then only knows how many
    /// days, not which. Setting them also sets `sportDaysPerWeek`.
    @Published var sportWeekdays: [Int] {
        didSet {
            if !sportWeekdays.isEmpty { sportDaysPerWeek = sportWeekdays.count }
            save()
        }
    }
    @Published var onboardingDone: Bool { didSet { save() } }

    /// Primary sport (first selected), for logic that needs a single sport such
    /// as the plan template. nil when no sport is selected.
    var practicedSportID: String? { practicedSportIDs.first }

    private let key = "spartanbody_profile"

    private init() {
        if let data = UserDefaults.standard.data(forKey: "spartanbody_profile"),
           let saved = try? JSONDecoder().decode(ProfileData.self, from: data) {
            name          = saved.name
            age           = saved.age
            sex           = saved.sex ?? .male
            weightKg      = saved.weightKg
            targetWeightKg = saved.targetWeightKg ?? saved.weightKg
            heightCm      = saved.heightCm
            goal          = saved.goal
            activityLevel = saved.activityLevel
            // Migrate old single-sport data into the new array.
            if let ids = saved.practicedSportIDs {
                practicedSportIDs = ids
            } else if let single = saved.practicedSportID {
                practicedSportIDs = [single]
            } else {
                practicedSportIDs = []
            }
            sportDaysPerWeek = saved.sportDaysPerWeek ?? 0
            sportWeekdays = saved.sportWeekdays ?? []
            onboardingDone = saved.onboardingDone
        } else {
            name          = ""
            age           = 25
            sex           = .male
            weightKg      = 75
            targetWeightKg = 75
            heightCm      = 175
            goal          = .gainMuscle
            activityLevel = .moderate
            practicedSportIDs = []
            sportDaysPerWeek = 0
            sportWeekdays = []
            onboardingDone = false
        }
    }

    // BMR via Mifflin-St Jeor (sex-specific constant)
    var bmr: Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.bmrConstant
    }

    /// Average daily calories burned by sport practice, assuming ~60-minute
    /// sessions, spread across the week so daily targets stay stable. With
    /// several sports we use their average burn rate over the total days.
    var sportDailyCalorieBonus: Int {
        guard sportDaysPerWeek > 0 else { return 0 }
        let rates = practicedSportIDs.compactMap { SportLibrary.byID($0)?.kcalPerMinute }
        guard !rates.isEmpty else { return 0 }
        let avgRate = rates.reduce(0, +) / Double(rates.count)
        return Int(avgRate * 60.0 * Double(sportDaysPerWeek) / 7.0)
    }

    /// Lowest daily target the app will suggest, the same floor the coach's
    /// plan uses. Without it a small, sedentary woman aiming to lose weight
    /// was shown targets around 700 kcal before her first plan existed.
    var calorieFloor: Int { sex == .female ? 1200 : 1500 }

    /// Maintenance plus the goal's adjustment, before the floor. The coach
    /// works from this (it applies the same floor itself, and needs the raw
    /// number to tell the user their real maintenance).
    var rawCalorieTarget: Int {
        Int(bmr * activityLevel.multiplier) + goal.dailyCalorieAdjustment + sportDailyCalorieBonus
    }

    /// The daily target shown to the user.
    var dailyCalorieTarget: Int { max(rawCalorieTarget, calorieFloor) }

    var dailyProteinTarget: Int {
        var perKg: Double
        switch goal {
        case .gainMuscle: perKg = 2.0
        case .loseWeight: perKg = 1.8
        case .stayFit:    perKg = 1.5
        }
        // Athletes practicing a sport 2+ days on top of the gym recover better
        // with a bit more protein.
        if !practicedSportIDs.isEmpty && sportDaysPerWeek >= 2 { perKg += 0.2 }
        return Int(weightKg * min(perKg, 2.2))
    }

    var bmi: Double {
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }

    var bmiCategory: String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }

    private func save() {
        let data = ProfileData(name: name, age: age, sex: sex, weightKg: weightKg,
                               targetWeightKg: targetWeightKg,
                               heightCm: heightCm, goal: goal,
                               activityLevel: activityLevel,
                               practicedSportIDs: practicedSportIDs,
                               sportDaysPerWeek: sportDaysPerWeek,
                               sportWeekdays: sportWeekdays,
                               onboardingDone: onboardingDone)
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}

private struct ProfileData: Codable {
    var name: String
    var age: Int
    var sex: BiologicalSex? = nil       // Optional for backward compatibility
    var weightKg: Double
    var targetWeightKg: Double? = nil   // Optional for backward compatibility
    var heightCm: Double
    var goal: FitnessGoal
    var activityLevel: ActivityLevel
    var practicedSportID: String? = nil   // Legacy single-sport (migrated on load)
    var practicedSportIDs: [String]? = nil // New multi-sport; nil for old saves
    var sportDaysPerWeek: Int? = nil      // Optional for backward compatibility
    var sportWeekdays: [Int]? = nil       // nil for saves before it existed
    var onboardingDone: Bool
}
