import Foundation

// Standalone checks for the coach engine, compiled against the app's real
// sources and run in the iOS simulator. Each scenario is a made-up history.

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  PASS  " : "  FAIL  ", what)
    if !ok { failures += 1 }
}

let now = Date()
let day: TimeInterval = 86_400

func session(daysAgo: Double, _ lifts: [(String, Double, Int, Int)]) -> WorkoutSession {
    let start = now.addingTimeInterval(-daysAgo * day)
    return WorkoutSession(
        name: "S", startedAt: start, finishedAt: start.addingTimeInterval(3600),
        exercises: lifts.map { id, kg, reps, sets in
            SessionExercise(exerciseID: id, sets: (1...sets).map {
                SessionSet(setNumber: $0, weight: kg, reps: reps, completed: true)
            })
        })
}

func inputs(goal: FitnessGoal = .gainMuscle, level: ActivityLevel = .moderate,
            sessions: [WorkoutSession] = [], weighIns: [WeightEntry] = [],
            calories: [Double] = Array(repeating: 0, count: 7),
            planned: Int? = nil, block: Int = 1, adj: Int = 0, canAdjust: Bool = true,
            context: String = "", sport: String? = nil, sportDays: Int = 0,
            weekdays: [Int] = [], sportSessions: Int = 0,
            streak: Int = 0) -> CoachInputs {
    CoachInputs(goal: goal, activityLevel: level, sex: .male, weightKg: 80, heightCm: 178,
                bmi: 25.2, bmiCategory: "Overweight", baseCalories: 2600, protein: 160,
                sportID: sport, sportDaysPerWeek: sportDays, sportWeekdays: weekdays,
                extraContext: context,
                sessions: sessions, weighIns: weighIns, dailyCalories: calories,
                currentStreak: streak, sportSessionsLast7: sportSessions,
                previousPlannedSessions: planned, blockWeek: block,
                calorieAdjustment: adj, canAdjustCalories: canAdjust, now: now, seed: 42)
}

func weighIns(start: Double, perWeek: Double, days: Int = 15) -> [WeightEntry] {
    stride(from: days, through: 0, by: -3).map { d in
        WeightEntry(date: now.addingTimeInterval(-Double(d) * day),
                    weightKg: start + perWeek * Double(days - d) / 7)
    }
}

// ── 1. First plan ever ───────────────────────────────────────────────────
print("1. Primera semana, sin historial")
do {
    let d = CoachAnalyzer.analyze(inputs())
    check(d.report.volume == .firstWeek, "volumen = firstWeek (\(d.report.volume))")
    check(d.trainingDays == 4, "moderado → 4 días (\(d.trainingDays))")
    check(d.weeklyCalories == 2600, "calorías sin tocar (\(d.weeklyCalories))")
    let plan = LocalCoachService.generatePlan(inputs())
    let heavy = plan.weeklySchedule.filter { $0.intensity == .heavy }
    check(heavy.count == 2, "2 días pesados (\(heavy.count))")
    // No two heavy days back to back.
    let seq = plan.weeklySchedule.map { $0.intensity == .heavy }
    check(!zip(seq, seq.dropFirst()).contains { $0 && $1 }, "nunca dos pesados seguidos")
    let bench = heavy.flatMap(\.exercises).first { $0.hasPrefix("Bench Press") } ?? "—"
    check(bench.contains("RPE 8"), "sin historial → RPE en vez de kilos: \(bench)")
}

// ── 2. Low adherence ─────────────────────────────────────────────────────
print("2. Hizo 1 de 4 entrenos")
do {
    let d = CoachAnalyzer.analyze(inputs(sessions: [session(daysAgo: 3, [("bench_press", 60, 8, 3)])],
                                         planned: 4))
    check(d.report.volume == .reduced, "volumen reducido (\(d.report.volume))")
    check(d.trainingDays == 3, "baja a 3 días (\(d.trainingDays))")
}

// ── 3. Full adherence ────────────────────────────────────────────────────
print("3. Hizo 4 de 4")
do {
    let s = (1...4).map { session(daysAgo: Double($0), [("bench_press", 80, 5, 5)]) }
    let i = inputs(sessions: s, planned: 4, block: 2)
    let d = CoachAnalyzer.analyze(i)
    check(d.report.volume == .increased, "sube volumen (\(d.report.volume))")
    let plan = LocalCoachService.generatePlan(i)
    let bench = plan.weeklySchedule.first { $0.intensity == .heavy }?.exercises.first ?? "—"
    check(bench.hasPrefix("Bench Press 6×5"), "principal +1 serie: \(bench)")
    // 80 kg × 5 × 5 all completed → progression adds 5 kg
    check(bench.contains("85 kg"), "hizo 80×5 completo → sube a 85: \(bench)")
    let light = plan.weeklySchedule.first { $0.intensity == .light && $0.exercises.contains { $0.hasPrefix("Incline") } }
    print("     día ligero:", light?.exercises.first ?? "—")
}

// ── 4. Losing too slowly while eating on target ──────────────────────────
print("4. Pierde peso demasiado lento")
do {
    let i = inputs(goal: .loseWeight, sessions: [session(daysAgo: 2, [("squat", 80, 5, 5)])],
                   weighIns: weighIns(start: 80, perWeek: -0.05),
                   calories: Array(repeating: 2600, count: 7), planned: 1, block: 2)
    let d = CoachAnalyzer.analyze(i)
    check(d.report.calorieChange == -150, "baja 150 kcal (\(d.report.calorieChange))")
    check(d.weeklyCalories == 2450, "objetivo 2450 (\(d.weeklyCalories))")
    print("     nota:", d.report.notes.last ?? "")
    let text = LocalCoachService.generatePlan(i).analysis
    check(text.contains("650"), "el resumen dice déficit de 650 (500 + 150 del coach)")
    check(!text.contains(" 500 "), "ya no dice 500 fijos")
    let fresh = LocalCoachService.generatePlan(inputs(goal: .loseWeight)).analysis
    check(fresh.contains("3100") && fresh.contains("500"), "primera semana: mantenimiento 3100 y déficit 500")
}

// ── 5. Eating far over target ────────────────────────────────────────────
print("5. Come un 30% más de su objetivo")
do {
    let i = inputs(goal: .loseWeight, sessions: [session(daysAgo: 2, [("squat", 80, 5, 5)])],
                   weighIns: weighIns(start: 80, perWeek: 0.2),
                   calories: Array(repeating: 3400, count: 7), planned: 1, block: 2)
    let d = CoachAnalyzer.analyze(i)
    check(d.report.calorieChange == 0, "no toca calorías (\(d.report.calorieChange))")
}

// ── 6. Same-week regeneration must not cut twice ────────────────────────
print("6. Regenera a mitad de semana")
do {
    let i = inputs(goal: .loseWeight, weighIns: weighIns(start: 80, perWeek: 0),
                   calories: Array(repeating: 2450, count: 7), adj: -150, canAdjust: false)
    let d = CoachAnalyzer.analyze(i)
    check(d.weeklyCalories == 2450, "mantiene el ajuste previo (\(d.weeklyCalories))")
    check(d.report.notes.contains { $0.contains("kcal.kept") || $0.contains("-150") }, "explica que mantiene el ajuste: \(d.report.notes.last ?? "")")
}

// ── 7. Deload week ───────────────────────────────────────────────────────
print("7. Semana 4 del ciclo")
do {
    let s = (1...3).map { session(daysAgo: Double($0 * 2), [("squat", 100, 5, 5)]) }
    let plan = LocalCoachService.generatePlan(inputs(sessions: s, planned: 4, block: 4))
    check(plan.report?.volume == .deload, "descarga (\(String(describing: plan.report?.volume)))")
    check(plan.weeklySchedule.filter(\.isWorkout).allSatisfy { $0.intensity == .deload },
          "todos los días de entreno en descarga")
}

// ── 8. Diet adds up ──────────────────────────────────────────────────────
print("8. La dieta cuadra")
for goal in [FitnessGoal.loseWeight, .gainMuscle, .stayFit] {
    let plan = LocalCoachService.generatePlan(inputs(goal: goal))
    let days = plan.weeklyMeals
    let avg = Double(days.compactMap { $0.target?.kcal }.reduce(0, +)) / Double(days.count)
    check(abs(avg - 2600) / 2600 < 0.01, "\(goal): media semanal = objetivo (\(Int(avg)))")
    var worst = 0.0, pLo = 9.0, pHi = 0.0, cLo = 9.0
    for d in days {
        guard let t = d.target, let tot = d.totals else { continue }
        worst = max(worst, abs(Double(tot.kcal - t.kcal)) / Double(t.kcal))
        pLo = min(pLo, Double(tot.protein) / Double(t.protein))
        pHi = max(pHi, Double(tot.protein) / Double(t.protein))
        cLo = min(cLo, Double(tot.carbs) / Double(t.carbs))
    }
    check(worst < 0.10, "\(goal): kcal de cada día a ±10% (peor \(Int(worst * 100))%)")
    check(pLo >= 0.85 && pHi <= 1.30, "\(goal): proteína entre 85% y 130% (\(Int(pLo * 100))–\(Int(pHi * 100))%)")
    check(cLo >= 0.70, "\(goal): carbos ≥70% del objetivo (peor \(Int(cLo * 100))%)")
    // Variety: nothing more than 3 times a week, never the same dish on
    // consecutive days.
    var counts: [String: Int] = [:]
    for d in days { for m in d.meals ?? [] where m.recipeID != nil { counts[m.recipeID!, default: 0] += 1 } }
    check((counts.values.max() ?? 0) <= 3, "\(goal): ninguna receta más de 3 veces (máx \(counts.values.max() ?? 0), \(counts.count) distintas)")
    let ids = days.map { Set(($0.meals ?? []).compactMap(\.recipeID)) }
    check(!zip(ids, ids.dropFirst()).contains { !$0.intersection($1).isEmpty }, "\(goal): no repite plato en días seguidos")
    let heavy = days.first { $0.intensity == .heavy }?.target?.carbs ?? 0
    let rest  = days.first { $0.intensity == .rest }?.target?.carbs ?? 0
    check(heavy > rest, "\(goal): más carbos en pesado (\(heavy) g) que en descanso (\(rest) g)")
}

// ── 9. Bad knee: swapped lift keeps no load, name is whole ──────────────
print("9. Rodilla mala")
do {
    let s = [session(daysAgo: 2, [("squat", 100, 5, 5), ("bench_press", 80, 5, 5)])]
    let plan = LocalCoachService.generatePlan(inputs(sessions: s, planned: 1, block: 2,
                                                     context: "tengo mala la rodilla"))
    let all = plan.weeklySchedule.flatMap(\.exercises)
    check(!all.contains { $0.contains("Back Glute") }, "sin nombres a medias ('Back Glute Bridge')")
    check(!all.contains { $0.hasPrefix("Back Squat") }, "sin sentadilla")
    let bridge = all.first { $0.hasPrefix("Glute Bridge") } ?? "—"
    check(!bridge.contains("kg"), "el sustituto no hereda los kilos: \(bridge)")
}

// ── 10. Plant-based menu ─────────────────────────────────────────────────
print("10. Vegano")
do {
    let plan = LocalCoachService.generatePlan(inputs(context: "soy vegano"))
    let ids = Set(plan.weeklyMeals.flatMap { $0.meals ?? [] }.compactMap(\.recipeID))
    let pool = Dictionary(uniqueKeysWithValues: RecipeDatabase.all.map { ($0.id, $0.tags) })
    check(ids.allSatisfy { pool[$0]?.contains("Vegan") == true || pool[$0]?.contains("Vegetarian") == true },
          "solo recetas veganas/vegetarianas (\(ids.count) distintas)")
    let foods = Set(plan.weeklyMeals.flatMap { $0.meals ?? [] }.flatMap { $0.items ?? [] }.map(\.foodID))
    check(!foods.contains("whey_protein") && !foods.contains("greek_yogurt"), "sin lácteos en meriendas")
}

// ── 11. BJJ practitioner ─────────────────────────────────────────────────
print("11. BJJ 3 días/semana")
do {
    let i = inputs(sport: "bjj", sportDays: 3)
    let d = CoachAnalyzer.analyze(i)
    check(d.trainingDays == 3, "moderado − BJJ → 3 días de gym (\(d.trainingDays))")
    let plan = LocalCoachService.generatePlan(i)
    let support = plan.weeklySchedule.first { $0.exercises.contains { $0.hasPrefix("Dead Hang") } }
    check(support?.intensity == .light, "el día de soporte BJJ es ligero")
}


// ── 12. BJJ Mon/Wed/Fri: gym placed around the classes ──────────────────
print("12. BJJ lunes, miércoles y viernes")
for (goal, level, wd) in [(FitnessGoal.gainMuscle, ActivityLevel.moderate, [2, 4, 6]),
                          (.loseWeight, .moderate, [2, 4, 6]),
                          (.gainMuscle, .active, [2, 3, 4, 6])] {
    let i = inputs(goal: goal, level: level, sport: "bjj", sportDays: wd.count, weekdays: wd)
    let plan = LocalCoachService.generatePlan(i)
    let sched = plan.weeklySchedule
    let sport = WeeklyPlanner.sportDayIndices(i)
    check(sport.count == wd.count, "\(goal): \(wd.count) días de clase en la semana")
    check(sport.allSatisfy { sched[$0].isSportDay }, "\(goal): cada día de clase marcado como BJJ")
    let heavy = sched.indices.filter { sched[$0].intensity == .heavy }
    check(heavy.allSatisfy { !sport.contains($0) }, "\(goal): ningún día pesado cae en día de clase")
    check(heavy.allSatisfy { !sport.contains(($0 + 1) % 7) }, "\(goal): nunca pesado el día antes de clase")
    let onSport = sched.indices.filter { sport.contains($0) && sched[$0].isWorkout }
    check(onSport.allSatisfy { sched[$0].intensity == .light && sched[$0].exercises.count <= 4 },
          "\(goal): si hay gym el día de clase, ligero y corto (\(onSport.count) casos)")
    let meals = plan.weeklyMeals
    let sportCarbs = sport.compactMap { meals[$0].target?.carbs }.min() ?? 0
    let restCarbs = meals.filter { $0.intensity == .rest }.compactMap { $0.target?.carbs }.max() ?? 0
    check(sportCarbs > restCarbs, "\(goal): más carbos en día de clase (\(sportCarbs) g) que en descanso (\(restCarbs) g)")
    print("     " + sched.map { d in
        (d.intensity?.rawValue ?? "-") + (d.isSportDay && d.isWorkout ? "+bjj" : "") }.joined(separator: " · "))
}

// ── 13. Way more classes than planned: no extra gym volume ──────────────
print("13. Hizo 5 clases de BJJ con 3 previstas")
do {
    let s = (1...3).map { session(daysAgo: Double($0 * 2), [("bench_press", 80, 5, 5)]) }
    let i = inputs(sessions: s, planned: 3, block: 2, sport: "bjj", sportDays: 3,
                   weekdays: [2, 4, 6], sportSessions: 5)
    let d = CoachAnalyzer.analyze(i)
    check(d.report.volume == .kept, "no sube volumen (\(d.report.volume))")
    check(d.report.sportSessions == 5, "registra las 5 clases")
}


// ── 14. Weekly review ────────────────────────────────────────────────────
print("14. Historial semanal")
do {
    var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
    let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!.start
    let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!
    func day(_ weekStart: Date, _ i: Int) -> Date { cal.date(byAdding: .day, value: i, to: weekStart)! }
    func base() -> WeeklyReviewEngine.Inputs {
        var food: [Date: (kcal: Double, protein: Double)] = [:]
        var h = HealthDailyHistory()
        for back in 0..<35 {
            let d = cal.startOfDay(for: cal.date(byAdding: .day, value: -back, to: now)!)
            food[d] = (2200, 155); h.steps[d] = 9000; h.sleepHours[d] = 7.6
            h.restingHR[d] = 55; h.hrv[d] = 60
        }
        let sessions = (0..<4).map { i -> WorkoutSession in
            let t = day(lastWeek, i * 2).addingTimeInterval(18 * 3600)
            return WorkoutSession(name: "S", startedAt: t, finishedAt: t.addingTimeInterval(3600), exercises: [])
        }
        return .init(sessions: sessions, sportSessionDates: [day(lastWeek, 1)], weighIns: [],
                     food: food, health: h, calorieTarget: 2200, proteinTarget: 160,
                     defaultPlanned: 4, decisions: [], now: now, calendar: cal)
    }
    var i = base()
    var r = WeeklyReviewEngine.build(i, weeks: 1).first
    check(r?.focus == nil && (r?.score ?? 0) >= 90, "semana buena → sin enfoque, nota \(r?.score ?? 0)")
    check(r?.sportSessions == 1 && r?.workoutsDone == 4, "cuenta 4 entrenos y 1 clase")

    i = base(); for k in 0..<7 { i.health.sleepHours[day(lastWeek, k)] = 5.8 }
    r = WeeklyReviewEngine.build(i, weeks: 1).first
    check(r?.focus == .sleep, "duerme 5 h 48 → enfoque sueño (\(String(describing: r?.focus)))")

    i = base(); for k in 0..<7 { i.health.sleepHours[day(lastWeek, k)] = 6.8
        i.health.restingHR[day(lastWeek, k)] = 61; i.health.hrv[day(lastWeek, k)] = 50 }
    r = WeeklyReviewEngine.build(i, weeks: 1).first
    check(r?.focus == .recovery, "pulso +6 y HRV −17% → enfoque recuperación (\(String(describing: r?.focus)))")
    check(r.map { abs(($0.restingHRBaseline ?? 0) - 55) < 0.1 } == true, "la media personal sale de las 3 semanas anteriores")

    i = base(); for k in 0..<7 { i.food[day(lastWeek, k)] = (2200, 105) }
    r = WeeklyReviewEngine.build(i, weeks: 1).first
    check(r?.focus == .protein, "105 g de 160 → enfoque proteína (\(String(describing: r?.focus)))")

    i = base(); i.sessions = Array(i.sessions.prefix(1))
    i.decisions = [CoachDecision(date: day(lastWeek, 0), plannedWorkouts: 3, notes: ["x"])]
    r = WeeklyReviewEngine.build(i, weeks: 1).first
    check(r?.workoutsPlanned == 3, "lo previsto sale del plan del coach, no del perfil")
    check(r?.focus == .training, "1 de 3 entrenos → enfoque entreno (\(String(describing: r?.focus)))")
    check(r?.coachNotes == ["x"], "guarda lo que decidió el coach esa semana")

    // Watchless user: no HRV/resting HR → no recovery area, no crash
    i = base(); i.health.restingHR = [:]; i.health.hrv = [:]
    r = WeeklyReviewEngine.build(i, weeks: 1).first
    check(r?.score(.recovery) == nil, "sin reloj: no hay área de recuperación")

    // Empty history
    let empty = WeeklyReviewEngine.Inputs(sessions: [], sportSessionDates: [], weighIns: [], food: [:],
        health: HealthDailyHistory(), calorieTarget: 2000, proteinTarget: 150, defaultPlanned: 3,
        decisions: [], now: now, calendar: cal)
    check(WeeklyReviewEngine.build(empty, weeks: 8).isEmpty, "sin datos: historial vacío, no semanas a cero")

    // A weigh-in from before the user started doesn't create a 0-score week
    var early = base()
    let twoBack = cal.date(byAdding: .weekOfYear, value: -2, to: thisWeek)!
    early.food = early.food.filter { $0.key >= lastWeek }
    early.weighIns = [WeightEntry(date: day(twoBack, 3), weightKg: 80)]
    early.health = HealthDailyHistory()
    check(WeeklyReviewEngine.build(early, weeks: 4).count == 1, "semanas antes de empezar no salen")

    // Backfill: 8 weeks of data → 8 reviews, newest first
    let many = WeeklyReviewEngine.build(base(), weeks: 4)
    check(many.count == 4 && many.first!.weekStart > many.last!.weekStart, "rellena semanas pasadas, la más reciente primero (\(many.count))")
}

// ── Sample output ────────────────────────────────────────────────────────
print("\n── Ejemplo: ganar músculo, 4 de 4 hechos, semana 2 ──")
let sample = LocalCoachService.generatePlan(inputs(
    sessions: (1...4).map { session(daysAgo: Double($0), [("bench_press", 80, 5, 5), ("squat", 100, 5, 5)]) },
    planned: 4, block: 2))
for d in sample.weeklySchedule {
    print(" \(d.intensity?.rawValue ?? "-")\t\(d.focus)")
    if d.isWorkout { d.exercises.forEach { print("        \($0)") } }
}
if let m = sample.weeklyMeals.first(where: { $0.intensity == .heavy }), let t = m.target, let tot = m.totals {
    print("\n Menú día pesado — objetivo \(t.kcal) kcal / P\(t.protein) C\(t.carbs) G\(t.fat)")
    for meal in m.meals ?? [] {
        let portion = meal.servings.map { "×\($0)" }
            ?? (meal.items ?? []).map { "\($0.name) \($0.grams)g" }.joined(separator: " + ")
        print("   \(meal.slot.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(meal.name) \(portion)  \(meal.kcal) kcal P\(meal.protein)")
    }
    print("   total     \(tot.kcal) kcal P\(tot.protein) C\(tot.carbs) G\(tot.fat)")
}

print(failures == 0 ? "\nTODO OK" : "\n\(failures) FALLOS")
exit(failures == 0 ? 0 : 1)
