import Foundation

// Things Spartan can do, not just say: shorten or ease today's workout, move
// it to another day, change a meal, rebuild the week around what he's learned,
// and record how hard a session felt. They're offered as buttons in the chat
// so nothing changes until the user taps.

struct ChatAction: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case shorten, ease, move, swapMeal, rebuild, rpe
    }
    var id = UUID()
    var kind: Kind
    var label: String
    /// Day index for `move`, RPE for `rpe`.
    var number: Int? = nil
    /// Meal slot for `swapMeal`, session id for `rpe`.
    var payload: String? = nil
    var done = false
}

extension Notification.Name {
    /// A gym session was saved; `object` is its UUID.
    static let sbWorkoutFinished = Notification.Name("sb.workoutFinished")
}

@MainActor
enum SpartanActions {
    private static func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
    /// Weekday names stay capitalised in English only ("move it to Sunday",
    /// "pasarlo al domingo").
    private static func dayName(_ s: String) -> String {
        LanguageManager.shared.selectedCode == "en" ? s : s.lowercased()
    }
    private static func F(_ k: String, _ a: CVarArg...) -> String {
        String(format: L(k), locale: .current, arguments: a)
    }

    // MARK: Offers

    /// The reply and buttons for a request that changes the plan, or nil
    /// when the topic isn't one.
    static func offer(for topic: CoachTopic?, message: String) -> (text: String, actions: [ChatAction])? {
        let plans = PlanStore.shared
        let today = plans.todayPlan
        switch topic {
        case .shortToday:
            guard let day = today, day.isWorkout else { return (L("spartan.act.noWorkout"), []) }
            guard day.exercises.count > 3 else { return (L("spartan.act.alreadyShort"), []) }
            let keep = day.exercises.prefix(3).map(EXLPlanLine).map { "• " + $0 }.joined(separator: "\n")
            return (F("spartan.act.short.offer", keep), [ChatAction(kind: .shorten, label: L("spartan.act.short.button"))])

        case .easyToday:
            guard let day = today, day.isWorkout else { return (L("spartan.act.restAlready"), []) }
            var actions = [ChatAction(kind: .ease, label: L("spartan.act.ease.button"))]
            if let first = plans.movableDays().first {
                actions.append(ChatAction(kind: .move, label: F("spartan.act.move.button", dayName(first.name)),
                                          number: first.index))
            }
            return (L("spartan.act.ease.offer"), actions)

        case .moveWorkout:
            guard let day = today, day.isWorkout else { return (L("spartan.act.noWorkout"), []) }
            let days = plans.movableDays().prefix(3)
            guard !days.isEmpty else {
                return (L("spartan.act.move.none"), [ChatAction(kind: .ease, label: L("spartan.act.ease.button"))])
            }
            return (L("spartan.act.move.offer"), days.map {
                ChatAction(kind: .move, label: F("spartan.act.move.button", dayName($0.name)), number: $0.index)
            })

        case .swapMeal:
            guard let meals = plans.todayMeals?.meals, !meals.isEmpty else { return (L("chat.faq.noPlan"), []) }
            let swappable = meals.filter { $0.recipeID != nil }
            var slots = slotsNamed(in: message).filter { s in swappable.contains { $0.slot == s } }
            // "No me gusta el salmón": the meal of today that has it.
            if slots.isEmpty, let food = SpartanMemory.dislikedFood(in: message) {
                slots = swappable.filter { m in
                    SpartanMemory.fold(NSLocalizedString(m.name, comment: "") + " " + m.name).contains(food)
                }.map(\.slot)
            }
            if slots.isEmpty { slots = swappable.map(\.slot) }
            var actions = slots.map { slot -> ChatAction in
                let meal = swappable.first { $0.slot == slot }!
                return ChatAction(kind: .swapMeal,
                                  label: F("spartan.act.swap.button", L(slot.labelKey).lowercased(),
                                           NSLocalizedString(meal.name, comment: "")),
                                  payload: slot.rawValue)
            }
            var text = L(actions.count == 1 ? "spartan.act.swap.offer.one" : "spartan.act.swap.offer")
            if let food = SpartanMemory.dislikedFood(in: message) {
                text = F("spartan.act.swap.dislike", food) + "\n\n" + text
                actions.append(ChatAction(kind: .rebuild, label: L("spartan.act.rebuild.menus")))
            }
            return (text, actions)

        default:
            return nil
        }
    }

    /// Something learned that the plan should follow: offer to rebuild it.
    static func rebuildOffer(for learned: [SpartanFact]) -> ChatAction? {
        guard PlanStore.shared.plan != nil,
              learned.contains(where: { [.injury, .equipment, .diet, .schedule].contains($0.kind) }) else { return nil }
        return ChatAction(kind: .rebuild, label: L("spartan.act.rebuild.button"))
    }

    private static func slotsNamed(in message: String) -> [PlannedMeal.MealSlot] {
        let f = SpartanMemory.fold(message)
        let names: [(PlannedMeal.MealSlot, [String])] = [
            (.breakfast, ["desayun", "breakfast", "petit dej", "colazione", "cafe da manha"]),
            (.lunch, ["almuerzo", "comida", "lunch", "dejeuner", "pranzo", "almoco"]),
            (.dinner, ["cena", "dinner", "diner", "jantar"]),
        ]
        return names.filter { _, w in w.contains(where: f.contains) }.map(\.0)
    }

    // MARK: Doing it

    /// Carries out an action and returns Spartan's confirmation.
    static func perform(_ action: ChatAction) -> String {
        let plans = PlanStore.shared
        switch action.kind {
        case .shorten:
            guard plans.shortenToday() else { return L("spartan.act.failed") }
            let list = (plans.todayPlan?.exercises ?? []).map(EXLPlanLine).map { "• " + $0 }.joined(separator: "\n")
            return F("spartan.act.short.done", list)
        case .ease:
            return plans.easeToday() ? L("spartan.act.ease.done") : L("spartan.act.failed")
        case .move:
            guard let target = action.number else { return L("spartan.act.failed") }
            let name = plans.plan?.weeklySchedule[safe: target]?.day ?? ""
            return plans.moveToday(to: target) ? F("spartan.act.move.done", dayName(name)) : L("spartan.act.failed")
        case .swapMeal:
            guard let raw = action.payload, let slot = PlannedMeal.MealSlot(rawValue: raw),
                  let new = plans.swapTodayMeal(slot) else { return L("spartan.act.swap.none") }
            return F("spartan.act.swap.done", L(slot.labelKey).lowercased(),
                     NSLocalizedString(new.name, comment: ""), new.kcal, new.protein)
        case .rebuild:
            plans.rebuildForMemory()
            return L("spartan.act.rebuild.done")
        case .rpe:
            guard let rpe = action.number, let raw = action.payload, let id = UUID(uuidString: raw) else {
                return L("spartan.act.failed")
            }
            WorkoutStore.shared.setRPE(rpe, for: id)
            return L(rpe <= 6 ? "spartan.rpe.easy.done" : rpe >= 9 ? "spartan.rpe.max.done" : "spartan.rpe.ok.done")
        }
    }

    // MARK: After a workout

    /// Spartan's comment on a finished session, with buttons for how hard it was.
    static func recap(_ session: WorkoutSession) -> (text: String, actions: [ChatAction]) {
        let style = SpartanStyle.current
        let history = WorkoutStore.shared.history.filter { $0.id != session.id }
        var parts = [SpartanVoice.pick("spartan.recap.title.\(style.rawValue)", name: SpartanVoice.name)]

        let done = session.exercises.flatMap(\.sets).filter(\.completed)
        let volume = done.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let minutes = max(1, Int(session.duration / 60))
        let sets = String.localizedStringWithFormat(L("spartan.recap.sets"), done.count)
        parts.append(F("spartan.recap.stats", sets, number(volume), minutes))

        // Personal records: the heaviest completed set beats every earlier one.
        for e in session.exercises {
            guard let best = e.sets.filter({ $0.completed && $0.weight > 0 }).max(by: { $0.weight < $1.weight })
            else { continue }
            let before = history.flatMap(\.exercises).filter { $0.exerciseID == e.exerciseID }
                .flatMap(\.sets).filter(\.completed).map(\.weight).max() ?? 0
            if before > 0, best.weight > before,
               let ex = ExerciseDatabase.all.first(where: { $0.id == e.exerciseID }) {
                parts.append(F("spartan.recap.pr", EXL(ex.name), number(best.weight), best.reps))
            }
        }
        parts.append(L("spartan.recap.ask"))

        let id = session.id.uuidString
        let actions = [(5, "spartan.rpe.easy"), (7, "spartan.rpe.ok"), (8, "spartan.rpe.hard"), (10, "spartan.rpe.max")]
            .map { ChatAction(kind: .rpe, label: L($0.1), number: $0.0, payload: id) }
        return (parts.joined(separator: "\n\n"), actions)
    }

    private static func number(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.maximumFractionDigits = v == v.rounded() ? 0 : 1
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
