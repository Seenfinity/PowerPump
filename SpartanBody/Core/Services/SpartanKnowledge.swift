import Foundation

/// Answers built from the app's own exercise and food tables. They need no
/// language model, so Spartan gives them the same way on every iPhone.
@MainActor
enum SpartanKnowledge {
    private static func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
    private static func F(_ k: String, _ a: CVarArg...) -> String {
        String(format: L(k), locale: .current, arguments: a)
    }
    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// The topics answered here; when nothing is found, the on-device model
    /// (if there is one) gets the question instead.
    static let topics: Set<CoachTopic> = [.exerciseHowTo, .exerciseSwap, .muscleExercises, .foodInfo]

    static func answer(_ topic: CoachTopic?, question q: String) -> String? {
        switch topic {
        case .exerciseHowTo:   return howTo(q)
        case .exerciseSwap:    return alternatives(q)
        case .muscleExercises: return muscleGroup(in: q).map { exercises(for: $0, question: q) }
        case .foodInfo:        return food(q)
        default:               return nil
        }
    }

    // MARK: Matching names

    private static let stop: Set<String> = ["de", "del", "con", "a", "al", "la", "el", "en", "una", "un", "with",
                                            "the", "and", "y", "e", "et", "le", "les", "du", "des", "per", "alla",
                                            "ai", "il", "com", "da", "do", "na", "no", "para", "por", "sur", "on", "of"]
    /// Gear, muscles and nutrients: they break a tie between two names but
    /// never make a match on their own ("no tengo barra" is not "barbell row").
    private static let weak: Set<String> = ["barra", "barre", "bar", "barbell", "bilanciere", "mancuerna", "mancuernas",
                                            "dumbbell", "haltere", "halteres", "haltera", "manubri", "manubrio", "halter",
                                            "polea", "cable", "cavi", "poulie", "polia", "tumbado", "colgado",
                                            "suspendu", "sbarra", "suspenso", "pecho", "chest", "piernas", "legs",
                                            "gluteos", "glutes", "glutei", "fessier", "triceps", "tricipiti", "mano",
                                            "brazo", "braccio", "bras", "arm", "caminando", "walking", "inclinado",
                                            "incline", "inclinata", "proteina", "protein", "proteine", "proteinas",
                                            "calorias", "calories", "calorie", "grasa", "fat", "leche", "milk"]

    /// The item whose name best fits the question, or nil when none does.
    private static func best<T>(_ items: [T], in question: String, names: (T) -> [String]) -> T? {
        let words = fold(question).split(whereSeparator: { !$0.isLetter }).map(String.init)
        var top: (item: T, score: Double)?
        for item in items {
            var score = 0.0
            for name in names(item) {
                // "Chicken Breast (raw)": the part in brackets is a detail.
                let clean = fold(name).replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
                let parts = clean.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { !stop.contains($0) }
                var strong = false, s = 0.0, missing = 0
                for p in parts {
                    // Plurals and short forms: "huevo" fits "huevos", "dominadas" fits "dominada".
                    let hit = words.contains { w in
                        w == p || (p.count >= 4 && w.hasPrefix(p)) || (w.count >= 5 && p.hasPrefix(w))
                    }
                    if hit {
                        s += weak.contains(p) ? 0.3 : 1
                        if !weak.contains(p) { strong = true }
                    } else {
                        missing += 1
                    }
                }
                // Fewer extra words wins: "peso muerto" is the deadlift, not the Romanian one.
                if strong { score = max(score, s - 0.1 * Double(missing)) }
            }
            if score > (top?.score ?? 0) { top = (item, score) }
        }
        return top?.item
    }

    private static func exercise(in q: String) -> Exercise? {
        best(ExerciseDatabase.all, in: q) { ex in
            [ex.name, EXL(ex.name)] + ["es", "fr", "it", "pt-BR"].map { ExerciseStrings.value(ex.name, language: $0) }
        }
    }

    private static func muscleGroup(in q: String) -> MuscleGroup? {
        CoachTopic.muscleGroup(in: fold(q)).flatMap(MuscleGroup.init(rawValue:))
    }

    private static func line(_ ex: Exercise) -> String {
        "• " + EXL(ex.name) + ": \(ex.defaultSets) × " + EXLReps(ex.defaultReps)
    }

    private static func atHome(_ q: String) -> Bool {
        ["en casa", "at home", "sin equipo", "sin material", "sin pesas", "sin gimnasio", "no equipment", "no gym",
         "a la maison", "sans materiel", "a casa", "senza attrezz", "em casa", "sem equipamento"]
            .contains(where: fold(q).contains)
    }

    private static func noBarbell(_ q: String) -> Bool {
        ["sin barra", "no tengo barra", "no barbell", "without a barbell", "sans barre", "senza bilanciere",
         "sem barra"].contains(where: fold(q).contains)
    }

    // MARK: Exercises

    /// The library's own steps for an exercise, in the user's language.
    private static let formChecked: Set<String> = ["squat", "deadlift", "romanian_deadlift", "overhead_press",
                                                   "barbell_curl", "walking_lunge", "push_up", "plank"]

    static func howTo(_ q: String) -> String? {
        guard let ex = exercise(in: q) else { return nil }
        var parts = [F("chat.faq.howTo.head", EXL(ex.name)), F("chat.faq.howTo.setup", EXL(ex.setup))]
        parts.append(ex.steps.enumerated().map { "\($0.offset + 1). " + EXL($0.element) }.joined(separator: "\n"))
        if !ex.tips.isEmpty { parts.append(F("chat.faq.howTo.tips", ex.tips.map(EXL).joined(separator: " · "))) }
        parts.append(F("chat.faq.howTo.dose", ex.defaultSets, EXLReps(ex.defaultReps)))
        if let last = SpartanInsights.form(forExercise: ex.id) {
            parts.append(last)
        } else if formChecked.contains(ex.id) {
            parts.append(F("chat.faq.howTo.video", L("Workout"), L("form.card.title")))
        }
        return parts.joined(separator: "\n\n")
    }

    /// Two or three exercises that train the same muscles.
    static func alternatives(_ q: String) -> String? {
        guard let ex = exercise(in: q) else {
            return muscleGroup(in: q).map { exercises(for: $0, question: q) }
        }
        let muscles = Set([ex.primaryMuscle] + ex.secondaryMuscles)
        var pool = ExerciseDatabase.all.filter { $0.id != ex.id }
        if atHome(q) { pool = pool.filter { $0.location != .gym } }
        if noBarbell(q) || atHome(q) { pool = pool.filter { $0.equipment != .barbell } }
        let ranked = pool.map { other -> (Exercise, Int) in
            let shared = Set([other.primaryMuscle] + other.secondaryMuscles).intersection(muscles).count
            let same = other.category == ex.category ? 2 : 0
            let main = other.primaryMuscle == ex.primaryMuscle ? 2 : 0
            return (other, same + main + shared)
        }
        .filter { $0.1 >= 2 }
        .sorted { $0.1 > $1.1 }
        .prefix(3).map(\.0)
        guard !ranked.isEmpty else { return F("chat.faq.swap.none", EXL(ex.name)) }
        return F("chat.faq.swap.head", EXL(ex.name)) + "\n" + ranked.map(line).joined(separator: "\n")
            + "\n\n" + L("chat.faq.swap.tail")
    }

    /// The library's exercises for a muscle group, home-friendly when asked.
    static func exercises(for group: MuscleGroup, question q: String) -> String {
        // Glutes also get the leg lifts that work them hard.
        var pool = ExerciseDatabase.all.filter { ex in
            ex.category == group
                || (group == .glutes && ex.category == .legs && ex.secondaryMuscles.contains { $0.hasPrefix("Glute") })
        }
        // Their own category first: hip thrusts before squats for glutes.
        pool.sort { ($0.category == group ? 0 : 1) < ($1.category == group ? 0 : 1) }
        if atHome(q) {
            let home = pool.filter { $0.location != .gym }
            if !home.isEmpty { pool = home }
        }
        let name = L("chat.muscle." + group.rawValue.lowercased().replacingOccurrences(of: " ", with: ""))
        return F("chat.faq.muscle.head", name) + "\n" + pool.prefix(5).map(line).joined(separator: "\n")
            + "\n\n" + L("chat.faq.muscle.tail")
    }

    // MARK: Food

    static func food(_ q: String) -> String? {
        guard let item = best(FoodDatabase.all, in: q, names: { [$0.name, NSLocalizedString($0.name, comment: "")] })
        else { return nil }
        let n = item.per100g
        // "Eggs (whole)" reads "Eggs, whole" so the line has one set of brackets.
        let name = NSLocalizedString(item.name, comment: "")
            .replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "")
        func g(_ v: Double) -> String { String(format: v < 10 ? "%.1f" : "%.0f", locale: .current, v) }
        var text = F("chat.faq.food.line", name, Int(n.calories.rounded()),
                     g(n.protein), g(n.carbs), g(n.fat))
        if ["engorda", "fattening", "grossir", "ingrass"].contains(where: fold(q).contains) {
            text += "\n\n" + L("chat.faq.food.fattening")
        }
        return text + "\n\n" + F("chat.faq.food.tail", L("Home"), L("quick.logMeal"))
    }

    // MARK: Using the app

    /// Where things are, with the same labels the screens show.
    static func appHelp() -> String {
        [L("chat.help.intro"),
         F("chat.help.food", L("Home"), L("quick.logMeal")),
         F("chat.help.weight", L("Weight"), L("Home")),
         F("chat.help.train", L("Workout"), L("Start Empty Workout")),
         F("chat.help.form", L("Workout"), L("form.card.title")),
         F("chat.help.recipes", L("Recipes")),
         F("chat.help.goal", L("Profile"), L("Edit Profile")),
         F("chat.help.health", L("Profile"), L("Health & Data")),
         F("chat.help.settings", L("Profile"), L("Settings")),
         "",
         L("chat.help.spartan")].joined(separator: "\n")
    }
}
