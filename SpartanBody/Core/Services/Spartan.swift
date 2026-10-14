import Foundation

// Spartan: the coach's personality, memory and knowledge of the user's own
// numbers. Shared by both chat modes — the on-device model gets it as
// instructions, the basic answers are wrapped with it — so a phone without
// Apple Intelligence still talks to the same coach.

// MARK: - Style

enum SpartanStyle: String, CaseIterable, Identifiable {
    case motivator, direct, buddy

    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .motivator: return "🔥"
        case .direct:    return "🎯"
        case .buddy:     return "🤝"
        }
    }
    var nameKey: String { "spartan.style.\(rawValue)" }
    var blurbKey: String { "spartan.style.\(rawValue).blurb" }

    private static let key = "sb_spartan_style"
    /// nil until the user picks one; the chat asks on first open.
    static var saved: SpartanStyle? {
        get { UserDefaults.standard.string(forKey: key).flatMap(SpartanStyle.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }
    static var current: SpartanStyle { saved ?? .motivator }
}

// MARK: - Memory

/// What the user has told Spartan about themselves, in their own words.
/// Kept on the phone; the user can see and delete every item.
struct SpartanFact: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case injury, diet, schedule, equipment, event, preference
        var icon: String {
            switch self {
            case .injury:     return "bandage.fill"
            case .diet:       return "leaf.fill"
            case .schedule:   return "clock.fill"
            case .equipment:  return "house.fill"
            case .event:      return "calendar"
            case .preference: return "heart.fill"
            }
        }
    }
    var id = UUID()
    var kind: Kind
    var text: String
    var date = Date()
    /// For dislikes: the food itself ("salmón"), to keep it off the menu.
    var item: String? = nil
}

@MainActor
final class SpartanMemory: ObservableObject {
    static let shared = SpartanMemory()
    @Published private(set) var facts: [SpartanFact] = []
    private let key = "sb_spartan_memory"

    private init() {
        facts = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([SpartanFact].self, from: $0) } ?? []
    }

    /// Facts found in a message, if any. Returns what was newly learned.
    @discardableResult
    func learn(from message: String) -> [SpartanFact] {
        let found = Self.extract(message).filter { new in
            !facts.contains { $0.kind == new.kind && Self.fold($0.text) == Self.fold(new.text) }
        }
        guard !found.isEmpty else { return [] }
        facts.append(contentsOf: found)
        if facts.count > 25 { facts.removeFirst(facts.count - 25) }
        save()
        return found
    }

    func forget(_ fact: SpartanFact) { facts.removeAll { $0.id == fact.id }; save() }
    func forgetAll() { facts = []; save() }

    func facts(_ kind: SpartanFact.Kind) -> [SpartanFact] { facts.filter { $0.kind == kind } }

    /// What the plan should know, in the user's words. The coach engine reads
    /// it like the notes field: knee, shoulder, back, home, vegan, short on time…
    var planNotes: String {
        facts.filter { [.injury, .equipment, .diet, .schedule].contains($0.kind) }
            .map(\.text).joined(separator: ". ")
    }

    /// Recipes containing a food the user said they don't like.
    var bannedRecipeIDs: Set<String> {
        let dislikes = facts.compactMap(\.item).map(Self.fold).filter { $0.count >= 3 }
        guard !dislikes.isEmpty else { return [] }
        return Set(RecipeDatabase.all.filter { r in
            let words = ([r.name] + r.ingredients.map(\.name))
                .flatMap { [$0, NSLocalizedString($0, comment: "")] }
                .map(Self.fold).joined(separator: " ")
            return dislikes.contains { words.contains($0) }
        }.map(\.id))
    }

    /// "no me gusta el salmón" → "salmón". The phrases come before the food
    /// in all five languages; articles are dropped.
    static func dislikedFood(in sentence: String) -> String? {
        let f = fold(sentence)
        let lead = ["no me gusta", "no me gustan", "odio", "no soporto", "i don't like", "i dont like", "i hate",
                    "je n'aime pas", "je deteste", "non mi piace", "non mi piacciono", "odio",
                    "nao gosto de", "não gosto de", "detesto"]
        guard let hit = lead.first(where: { f.contains(fold($0)) }),
              let r = f.range(of: fold(hit)) else { return nil }
        let articles: Set<String> = ["el", "la", "los", "las", "un", "una", "the", "le", "les", "du", "des",
                                     "il", "lo", "gli", "i", "o", "a", "os", "as", "de", "comer", "eat"]
        let words = f[r.upperBound...].split(whereSeparator: { !$0.isLetter })
            .map(String.init).filter { !articles.contains($0) }
        guard let food = words.first, food.count >= 3 else { return nil }
        return food
    }

    private func save() {
        if let d = try? JSONEncoder().encode(facts) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Words that mark a sentence as worth remembering, in the five app
    /// languages, without accents. Questions alone ("¿qué como?") don't count.
    static let cues: [(SpartanFact.Kind, [String])] = [
        (.injury, ["me duele", "me dolio", "tengo dolor", "lesion", "lesionad", "operad", "tendinitis", "hernia",
                   "esguince", "it hurts", "hurts", "injur", "my knee", "my back", "my shoulder", "surgery",
                   "j'ai mal", "blesse", "blessure", "operee", "mi fa male", "infortun", "ho male", "operato",
                   "doi ", "dor no", "dor na", "machuc", "lesao", "operad"]),
        (.diet, ["vegano", "vegana", "vegan", "vegetarian", "vegetarien", "vegetariano", "vegetariana",
                 "sin lactosa", "intolerante", "lactose", "celiac", "sin gluten", "gluten free", "sans gluten",
                 "senza glutine", "sem gluten", "alergic", "allergic", "allergique", "allergico", "alergico",
                 "no como carne", "don't eat meat", "dont eat meat", "halal", "kosher", "no como pescado"]),
        (.schedule, ["por la manana", "por la tarde", "por la noche", "de madrugada", "in the morning",
                     "in the evening", "at night", "le matin", "le soir", "la mattina", "la sera", "de manha",
                     "a noite", "poco tiempo", "solo tengo", "only have", "no time", "peu de temps",
                     "poco tempo", "pouco tempo", "trabajo de", "i work", "turnos", "shifts"]),
        (.equipment, ["en casa", "at home", "a la maison", "a casa", "em casa", "no tengo pesas",
                      "sin gimnasio", "no gym", "without a gym", "solo mancuernas", "only dumbbells",
                      "solo bandas", "resistance bands", "kettlebell", "barra de dominadas", "pull-up bar"]),
        (.event, ["competicion", "competencia", "torneo", "campeonato", "boda", "vacaciones", "carrera de",
                  "competition", "tournament", "wedding", "holiday", "vacation", "a race", "competition",
                  "mariage", "vacances", "gara", "matrimonio", "vacanze", "campeonato", "casamento", "ferias"]),
        (.preference, ["me encanta", "me gusta", "odio", "no me gusta", "i love", "i hate", "i like",
                       "i don't like", "j'adore", "je deteste", "j'aime", "mi piace", "odio", "adoro", "eu amo"]),
    ]

    static func extract(_ message: String) -> [SpartanFact] {
        // Sentence by sentence, so a long message keeps only the relevant part.
        let sentences = message.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 6 }
        var out: [SpartanFact] = []
        for sentence in sentences {
            let f = " " + fold(sentence) + " "
            // A question about a food or an injury is not a fact about the user.
            let isQuestion = message.contains("?") && !f.contains(" soy ") && !f.contains(" tengo ")
                && !f.contains(" i'm ") && !f.contains(" i am ") && !f.contains(" me duele ")
            // "Today I only have 30 minutes" is about today, not about them.
            let isToday = [" hoy ", " today", "aujourd", " oggi ", " hoje "].contains(where: f.contains)
            for (kind, words) in cues where words.contains(where: f.contains) {
                if isToday && (kind == .schedule || kind == .equipment) { continue }
                if isQuestion && kind != .injury && !(kind == .preference && dislikedFood(in: sentence) != nil) { continue }
                let text = String(sentence.prefix(90))
                if !out.contains(where: { $0.kind == kind }) {
                    out.append(SpartanFact(kind: kind, text: text,
                                           item: kind == .preference ? dislikedFood(in: sentence) : nil))
                }
            }
        }
        return out
    }
}

// MARK: - The user's own numbers

/// Short sentences built from the user's real training, weight, sleep and
/// form data. Each one is nil when there isn't enough data to say anything
/// true.
@MainActor
enum SpartanInsights {
    private static func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
    private static func F(_ k: String, _ a: CVarArg...) -> String {
        String(format: L(k), locale: .current, arguments: a)
    }
    private static func num(_ v: Double, _ digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = .current
        f.minimumFractionDigits = v == v.rounded() ? 0 : 1
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Best recent working set and what to lift next time.
    static var topLift: String? {
        let history = WorkoutStore.shared.history
        let cutoff = Date().addingTimeInterval(-35 * 86_400)
        var best: (id: String, w: Double, r: Int)?
        for s in history where s.startedAt >= cutoff {
            for e in s.exercises {
                for set in e.sets where set.completed && set.weight > 0 {
                    if set.weight > (best?.w ?? 0) { best = (e.exerciseID, set.weight, set.reps) }
                }
            }
        }
        guard let best, let ex = ExerciseDatabase.all.first(where: { $0.id == best.id }) else { return nil }
        let next = ProgressionEngine.suggestion(for: best.id, history: history,
                                                targetReps: best.r, fallbackWeight: best.w)
        let name = EXL(ex.name)
        if next.weight > best.w {
            return F("spartan.data.topLift.up", name, num(best.w), best.r, num(next.weight), next.reps)
        }
        return F("spartan.data.topLift.hold", name, num(best.w), best.r)
    }

    /// Sessions this week against the plan.
    static var week: String? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? .now
        let done = WorkoutStore.shared.history.filter { $0.startedAt >= start && $0.finishedAt != nil }.count
            + RunStore.shared.history.filter { $0.startedAt >= start }.count
            + SportSessionStore.shared.history.filter { $0.startedAt >= start }.count
        let planned = PlanStore.shared.plan?.weeklySchedule.filter { $0.isWorkout || $0.isSportDay }.count ?? 0
        if planned > 0 { return F("spartan.data.week.plan", done, planned) }
        return done > 0 ? F("spartan.data.week", done) : nil
    }

    static var streak: String? {
        let s = WorkoutStore.shared.currentStreak
        return s >= 2 ? F("spartan.data.streak", s) : nil
    }

    /// Days since the last training of any kind, when it's been a while.
    static var away: Int? {
        let dates = WorkoutStore.shared.history.map(\.startedAt)
            + RunStore.shared.history.map(\.startedAt)
            + SportSessionStore.shared.history.map(\.startedAt)
        guard let last = dates.max() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return days >= 3 ? days : nil
    }

    static var weightTrend: String? {
        let e = ProgressStore.shared.entries(days: 28).sorted { $0.date < $1.date }
        guard e.count >= 3, let a = e.first, let b = e.last,
              b.date.timeIntervalSince(a.date) >= 7 * 86_400 else { return nil }
        let t0 = a.date
        let xs = e.map { $0.date.timeIntervalSince(t0) / 86_400 }, ys = e.map(\.weightKg)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        let perWeek = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / den * 7
        if abs(perWeek) < 0.1 { return L("spartan.data.weight.flat") }
        return F(perWeek < 0 ? "spartan.data.weight.down" : "spartan.data.weight.up", num(abs(perWeek)))
    }

    static var sleep: String? {
        let s = HealthKitService.shared.sleepLastNight
        guard s >= 3600 else { return nil }
        let h = Int(s) / 3600, m = Int(s) % 3600 / 60
        return F(s < 6.5 * 3600 ? "spartan.data.sleep.short" : "spartan.data.sleep.ok", h, m)
    }

    static var form: String? {
        guard let r = FormReportStore.shared.reports.first else { return nil }
        return form(r)
    }

    /// The latest form check of one library exercise ("squat", "deadlift"…).
    static func form(forExercise id: String) -> String? {
        let ids = ["squat": "squat", "deadlift": "deadlift", "romanianDeadlift": "romanian_deadlift",
                   "overheadPress": "overhead_press", "bicepCurl": "barbell_curl", "lunge": "walking_lunge"]
        return FormReportStore.shared.reports.first { ids[String(describing: $0.exercise)] == id }.flatMap(form)
    }

    private static func form(_ r: FormReport) -> String? {
        guard Date().timeIntervalSince(r.date) < 30 * 86_400 else { return nil }
        let ex = L(r.exercise.nameKey)
        if let issue = r.issues.first {
            return F("spartan.data.form.issue", ex, r.score, L("form.rule.\(issue.rule).title").lowercased())
        }
        return F("spartan.data.form.clean", ex, r.score)
    }

    /// The most relevant true sentence for a topic.
    static func line(for topic: CoachTopic?) -> String? {
        switch topic {
        case .strength, .power, .contactStrength, .repsWeight, .plateau, .gainMuscle, .volume, .restSets,
             .failure, .deload:
            return topLift ?? week
        case .exerciseSwap, .muscleExercises:
            // The top lift is about another exercise; the week is still true.
            return week
        case .exerciseHowTo:
            // The guide adds the form check of that same exercise itself.
            return nil
        case .comeback:
            return streak ?? week
        case .stress:
            return sleep
        case .calorieNeeds, .carbs:
            return weightTrend
        case .motivation, .trainingDays, .beginner, .homeWorkout:
            return streak ?? week
        case .sleep, .soreness:
            return sleep ?? week
        case .loseFat, .scaleWeight, .bellyFat, .recomp, .loseFast, .cheatMeal:
            return weightTrend
        case .warmUp, .stretching, .pain:
            return form
        case .generalTraining, .cardio, .endurance, nil:
            return week ?? topLift
        default:
            return nil
        }
    }

    /// Everything known, for the on-device model's instructions.
    static var all: [String] {
        [topLift, week, streak, weightTrend, sleep, form].compactMap { $0 }
    }
}

// MARK: - Voice

/// How Spartan wraps an answer: an opener, the content, a line from the
/// user's own data or memory, and a closer — each picked at random among
/// several so two answers in a row never sound the same.
@MainActor
enum SpartanVoice {
    private static func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
    private static var lastPick: [String: Int] = [:]

    /// One of the "|"-separated variants of a key, never the same twice in a row.
    static func pick(_ key: String, name: String = "") -> String {
        let options = L(key).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !options.isEmpty else { return "" }
        var i = Int.random(in: 0..<options.count)
        if options.count > 1, i == lastPick[key] { i = (i + 1) % options.count }
        lastPick[key] = i
        let text = options[i]
        guard text.contains("%@") else { return text }
        let who = name.isEmpty ? L("spartan.friend") : name
        return String(format: text, locale: .current, who)
    }

    static var name: String { UserProfile.shared.name.trimmingCharacters(in: .whitespaces) }

    static func wrap(_ body: String, topic: CoachTopic?, learned: [SpartanFact],
                     also: (topic: CoachTopic, body: String)? = nil, opener: Bool = true,
                     question: String = "") -> String {
        let style = SpartanStyle.current
        let careful = topic?.isSensitive == true
        var parts: [String] = []
        if !learned.isEmpty { parts.append(pick("spartan.learned.\(style.rawValue)")) }
        // An opener only for a real question, and only some of the time: a
        // coach who praises every message stops sounding like a person.
        // Pain, health and crash diets get none at all.
        if !careful, opener, asks(question), chance(0.5) {
            parts.append(pick("spartan.open.\(style.rawValue)", name: name))
        }
        parts.append(body)
        if let also {
            parts.append(pick("spartan.also") + "\n" + also.body)
        }
        let focus = also?.topic ?? topic
        if let memory = memoryLine(for: focus), !(careful && also == nil) { parts.append(memory) }
        if let data = SpartanInsights.line(for: focus) { parts.append(chance(0.6) ? linked(data) : data) }
        // The last word: always a caring one on sensitive subjects; otherwise
        // now and then, less from the direct coach, and never right after
        // Spartan has asked something back.
        let closing: Double = careful ? 1 : [.motivator: 0.6, .buddy: 0.5, .direct: 0.35][style] ?? 0.5
        if !(parts.last?.hasSuffix("?") ?? false), chance(closing) {
            parts.append(pick(careful ? "spartan.close.care" : "spartan.close.\(style.rawValue)", name: name))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

    /// "Por cierto, esta semana llevas…": a data line that reads as part of
    /// the conversation instead of a report.
    static func linked(_ line: String) -> String {
        guard let first = line.first else { return line }
        return pick("spartan.link") + " " + first.lowercased() + line.dropFirst()
    }

    /// Whether the message asks something, so "good question" fits.
    static func asks(_ message: String) -> Bool {
        if message.contains("?") || message.contains("¿") { return true }
        let first = message.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        return ["como", "que", "cuanto", "cuanta", "cuantos", "cuantas", "cual", "cuando", "donde", "por", "puedo",
                "debo", "es", "sirve", "how", "what", "which", "when", "why", "can", "should", "is", "do", "does",
                "comment", "combien", "quel", "quelle", "pourquoi", "est", "puis", "dois", "come", "quanto", "quanti",
                "quale", "perche", "posso", "devo", "quantas", "qual", "quando", "onde"].contains(first)
    }

    /// Ties the answer to something the user said before.
    static func memoryLine(for topic: CoachTopic?) -> String? {
        let memory = SpartanMemory.shared
        func quoted(_ f: SpartanFact) -> String { "«\(f.text)»" }
        switch topic {
        case .strength, .power, .contactStrength, .trainToday, .repsWeight, .warmUp, .generalTraining,
             .homeWorkout, .cardio, .endurance, .volume, .plateau:
            if let f = memory.facts(.injury).last {
                return String(format: L("spartan.memory.injury"), locale: .current, quoted(f))
            }
            if let f = memory.facts(.equipment).last {
                return String(format: L("spartan.memory.equipment"), locale: .current, quoted(f))
            }
        case .eatToday, .snacks, .breakfast, .proteinAmount, .preWorkout, .postWorkout, .cheapFood,
             .eatingOut, .loseFat, .gainMuscle:
            if let f = memory.facts(.diet).last {
                return String(format: L("spartan.memory.diet"), locale: .current, quoted(f))
            }
        case .motivation:
            if let f = memory.facts(.event).last {
                return String(format: L("spartan.memory.event"), locale: .current, quoted(f))
            }
        default: break
        }
        return nil
    }

    /// Spartan's first message of the day: today's plan plus one thing from
    /// the user's data.
    static func dailyCheckIn() -> String {
        let style = SpartanStyle.current
        var parts = [pick("spartan.hello.\(style.rawValue)", name: name)]
        if let day = PlanStore.shared.todayPlan {
            if day.isSportDay, let sport = day.sport.flatMap(SportLibrary.byID) {
                parts.append(String(format: L("spartan.today.sport"), locale: .current, L(sport.nameKey)))
            } else if day.isWorkout {
                parts.append(String(format: L("spartan.today.workout"), locale: .current, day.focus))
            } else {
                parts.append(L("spartan.today.rest"))
            }
        }
        // On a rest day "let's get back today" would contradict the plan.
        let restDay = PlanStore.shared.todayPlan.map { !$0.isWorkout && !$0.isSportDay } ?? false
        if let days = SpartanInsights.away, !restDay {
            parts.append(String(format: L("spartan.today.away.\(style.rawValue)"), locale: .current, days))
        } else if let sleep = SpartanInsights.sleep {
            parts.append(sleep)
        } else if let streak = SpartanInsights.streak {
            parts.append(streak)
        }
        if let event = SpartanMemory.shared.facts(.event).last {
            parts.append(String(format: L("spartan.memory.event"), locale: .current, "«\(event.text)»"))
        }
        parts.append(pick("spartan.ask.\(style.rawValue)"))
        return parts.joined(separator: "\n\n")
    }

    /// Questions to tap after an answer, so a conversation never dead-ends.
    static func followUps(after topic: CoachTopic?) -> [String] {
        switch topic {
        case .strength, .power, .contactStrength, .repsWeight, .volume, .plateau:
            return ["chat.suggest.restSets", "chat.suggest.postWorkout", "chat.suggest.creatine"]
        case .loseFat, .bellyFat, .loseFast, .scaleWeight, .recomp, .cheatMeal:
            return ["chat.suggest.eatToday", "chat.suggest.steps", "chat.suggest.cravings"]
        case .gainMuscle, .proteinAmount, .proteinChoose, .creatine, .supplements:
            return ["chat.suggest.eatToday", "chat.suggest.strength", "chat.suggest.sleep"]
        case .eatToday, .snacks, .breakfast, .preWorkout, .postWorkout, .cheapFood, .eatingOut:
            return ["chat.suggest.proteinAmount", "chat.suggest.trainToday", "chat.suggest.snacks"]
        case .trainToday, .warmUp, .stretching, .homeWorkout, .trainingDays, .beginner:
            return ["chat.suggest.warmUp", "chat.suggest.strength", "chat.suggest.preWorkout"]
        case .sleep, .soreness, .pain, .health:
            return ["chat.suggest.trainToday", "chat.suggest.sleep", "chat.suggest.motivation"]
        case .motivation:
            return ["chat.suggest.trainToday", "chat.suggest.homeWorkout", "chat.suggest.strength"]
        case .exerciseHowTo, .exerciseSwap, .muscleExercises, .failure, .deload:
            return ["chat.suggest.restSets", "chat.suggest.glutes", "chat.suggest.howSquat"]
        case .foodInfo, .calorieNeeds, .carbs:
            return ["chat.suggest.eatToday", "chat.suggest.foodEgg", "chat.suggest.proteinAmount"]
        case .comeback, .olderAdult, .teen, .trainingTime, .cramps, .cycle:
            return ["chat.suggest.trainToday", "chat.suggest.howSquat", "chat.suggest.warmUp"]
        case .stress:
            return ["chat.suggest.sleep", "chat.suggest.steps", "chat.suggest.motivation"]
        case .appHelp:
            return ["chat.suggest.trainToday", "chat.suggest.calories", "chat.suggest.foodEgg"]
        case .crisis:
            // Nothing that pulls the conversation back to training.
            return []
        default:
            return ["chat.suggest.trainToday", "chat.suggest.eatToday", "chat.suggest.strength"]
        }
    }
}
