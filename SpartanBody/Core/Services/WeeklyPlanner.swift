import Foundation

/// Builds the training week: which days are heavy, medium, light or rest, the
/// exercises of each session, and a load for every weighted lift.
///
/// The structure is daily undulating periodisation — the same muscles get a
/// heavy day (few reps, high load) and a light day (more reps, technique) in
/// the same week, and two heavy days never land back to back.
enum WeeklyPlanner {

    struct Week {
        var days: [DayPlan]
        /// Per day, the load suffix for each exercise name (" · 80 kg",
        /// " · RPE 8"). Kept apart so injury/home substitutions can run on
        /// the plain lines first: a swapped exercise must not inherit the
        /// original's load.
        var loads: [[String: String]]
    }

    static func week(_ i: CoachInputs, _ d: CoachAnalyzer.Decision, dayNames: [String]) -> Week {
        let fixed = self.layout(days: d.trainingDays, goal: i.goal)
        // With the user's sport days known, the gym sessions are placed
        // around them; otherwise the fixed pattern already spreads them well.
        let sportDays = sportDayIndices(i)
        let layout = sportDays.isEmpty ? fixed : place(fixed.compactMap { $0 }, around: sportDays)
        let sportName = i.sportID.map { NSLocalizedString(SportLibrary.byID($0)?.nameKey ?? $0, comment: "") }

        var days: [DayPlan] = []
        var loads: [[String: String]] = []
        let lastRest = layout.indices.last { layout[$0] == nil && !sportDays.contains($0) } ?? 6

        for (idx, entry) in layout.enumerated() {
            let name = dayNames[idx % dayNames.count]
            let isSport = sportDays.contains(idx)

            guard let entry else {
                if isSport, let sportName {
                    // The user's own practice: no gym, and the diet knows it's
                    // a hard day.
                    days.append(DayPlan(day: name, type: "sport", focus: sportName,
                                        exercises: [sportName], intensity: .sport, sport: i.sportID))
                    loads.append([:])
                    continue
                }
                // Rest: the day after training gets light movement, the last
                // rest day of the week is full rest.
                let afterTraining = idx > 0 && (layout[idx - 1] != nil || sportDays.contains(idx - 1))
                let exercises = idx == lastRest ? LocalCoachService.fullRestExercises()
                    : afterTraining ? LocalCoachService.activeRecoveryExercises()
                    : LocalCoachService.lightRecoveryExercises()
                days.append(DayPlan(day: name, type: "rest",
                                    focus: L(idx == lastRest ? "coach.focus.rest" : "coach.focus.activeRecovery"),
                                    exercises: exercises, intensity: .rest))
                loads.append([:])
                continue
            }
            let session = entry.0
            var intensity = entry.1

            if d.isDeload { intensity = .deload }
            // Coming back after two weeks off: nothing heavy yet.
            if d.report.volume == .comeback && intensity == .heavy { intensity = .medium }
            // Gym on a sport day (not enough free days): short and light, so
            // the practice isn't wrecked.
            if isSport && intensity != .deload { intensity = .light }

            var lines: [String] = []
            var dayLoads: [String: String] = [:]
            var slots = self.slots(for: session)
            if d.isBeginner { slots = slots.map(beginnerSwap) }
            if d.report.volume == .reduced, slots.count > 4 { slots.removeLast() }
            if isSport, slots.count > 4 { slots = Array(slots.prefix(4)) }

            for slot in slots {
                let (sets, reps) = scheme(for: slot, intensity: intensity,
                                          beginner: d.isBeginner, volume: d.report.volume,
                                          circuit: session == .conditioning)
                lines.append("\(slot.name) \(sets)×\(reps)")
                if let load = load(for: slot, reps: Int(reps) ?? 0, intensity: intensity,
                                   sessions: i.sessions, now: i.now) {
                    dayLoads[slot.name] = load
                }
            }
            var focus = L(session.focusKey)
            if isSport, let sportName { focus += " + " + sportName }
            days.append(DayPlan(day: name, type: "workout", focus: focus, exercises: lines,
                                intensity: intensity, sport: isSport ? i.sportID : nil))
            loads.append(dayLoads)
        }

        var week = Week(days: days, loads: loads)
        if let sportID = i.sportID, i.sportDaysPerWeek > 0 {
            applySportSupport(&week, sportID: sportID)
        }
        return week
    }

    /// Plan-day indices (0 = the day the plan starts) that fall on one of the
    /// user's sport weekdays.
    static func sportDayIndices(_ i: CoachInputs) -> Set<Int> {
        guard i.sportID != nil, !i.sportWeekdays.isEmpty else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: i.now)
        return Set((0..<7).filter { idx in
            guard let date = cal.date(byAdding: .day, value: idx, to: start) else { return false }
            return i.sportWeekdays.contains(cal.component(.weekday, from: date))
        })
    }

    /// Puts each gym session on the day that suits it best: heavy sessions
    /// first, away from sport days and from the day before one (you don't
    /// squat heavy the night before sparring), never next to another heavy
    /// day, and spread out rather than bunched.
    ///
    /// The week repeats, so "the day before a sport day" wraps: the last day
    /// of the plan is the day before next week's first.
    static func place(_ sessions: [(Session, DayIntensity)], around sport: Set<Int>) -> [(Session, DayIntensity)?] {
        var out: [(Session, DayIntensity)?] = Array(repeating: nil, count: 7)
        func rank(_ x: DayIntensity) -> Int { x == .heavy ? 0 : x == .medium ? 1 : 2 }
        let ordered = sessions.enumerated()
            .sorted { (rank($0.element.1), $0.offset) < (rank($1.element.1), $1.offset) }
            .map(\.element)

        for s in ordered {
            let heavy = s.1 == .heavy
            var best: Int?
            var bestScore = -Double.infinity
            for day in 0..<7 where out[day] == nil {
                var score = 0.0
                if sport.contains(day) { score -= heavy ? 16 : 6 }
                if heavy && sport.contains((day + 1) % 7) { score -= 8 }
                for n in [day - 1, day + 1] where (0..<7).contains(n) {
                    if let o = out[n] { score -= (heavy && o.1 == .heavy) ? 9 : 2 }
                }
                score -= Double(day) * 0.01          // earlier wins a tie
                if score > bestScore { bestScore = score; best = day }
            }
            guard let best else { continue }
            // A crowded week can leave no clean slot for a heavy session. Then
            // it becomes medium rather than land on, or the eve of, a class.
            var placed = s
            if heavy && (sport.contains(best) || sport.contains((best + 1) % 7)) {
                placed.1 = .medium
            }
            out[best] = placed
        }
        return out
    }

    /// Appends each load to its line, after substitutions have run. A line
    /// whose exercise was swapped (bad knee, home workout…) no longer matches
    /// by name and keeps no load — the original lift's kilos would be wrong.
    static func annotate(_ days: [DayPlan], with loads: [[String: String]]) -> [DayPlan] {
        zip(days, loads).map { day, dayLoads in
            var day = day
            day.exercises = day.exercises.map { line in
                let name = exerciseName(of: line)
                guard let load = dayLoads[name] else { return line }
                return line + load
            }
            return day
        }
    }

    /// "Back Squat 5×5" → "Back Squat".
    static func exerciseName(of line: String) -> String {
        guard let r = line.range(of: #"\s+\d+\s*[×x]\s*\d+"#, options: .regularExpression) else {
            return line
        }
        return String(line[line.startIndex..<r.lowerBound])
    }

    // MARK: - Week layout

    enum Session: Equatable {
        case upperHeavy, upperMedium, upperLight
        case lowerHeavy, lowerMedium, lowerLight
        case fullHeavy, fullMedium, fullLight
        case conditioning

        var focusKey: String {
            switch self {
            case .upperHeavy, .upperMedium, .upperLight: return "coach.focus.upper"
            case .lowerHeavy, .lowerMedium, .lowerLight: return "coach.focus.lower"
            case .fullHeavy, .fullMedium, .fullLight:    return "coach.focus.full"
            case .conditioning:                          return "coach.focus.conditioning"
            }
        }
    }

    /// Seven slots, index 0 = the day the plan starts. nil = rest.
    ///
    /// Heavy days sit apart, and each region (upper / lower) gets one heavy
    /// and one lighter session when there are enough days for it. Fat loss and
    /// general fitness swap a light lifting day for a conditioning circuit.
    static func layout(days: Int, goal: FitnessGoal) -> [(Session, DayIntensity)?] {
        let conditioningDay = goal != .gainMuscle
        switch days {
        case ...2:
            return [(.fullHeavy, .heavy), nil, nil, (.fullMedium, .medium), nil, nil, nil]
        case 3:
            return [(.fullHeavy, .heavy), nil,
                    conditioningDay ? (.conditioning, .light) : (.fullLight, .light), nil,
                    (.fullMedium, .medium), nil, nil]
        case 4:
            return [(.upperHeavy, .heavy), (.lowerLight, .light), nil,
                    conditioningDay ? (.conditioning, .light) : (.upperLight, .light),
                    (.lowerHeavy, .heavy), nil, nil]
        default:
            return [(.upperHeavy, .heavy), (.lowerLight, .light), nil,
                    (.upperMedium, .medium), (.lowerHeavy, .heavy),
                    conditioningDay ? (.conditioning, .light) : (.fullLight, .light), nil]
        }
    }

    // MARK: - Sessions

    enum Role { case main, secondary, accessory, core, timed }

    struct Slot {
        let name: String   // exercise library name (EXL translates it)
        let id: String?    // library id — links to history and loads
        let role: Role
    }

    private static func s(_ name: String, _ id: String?, _ role: Role) -> Slot {
        Slot(name: name, id: id, role: role)
    }

    static func slots(for session: Session) -> [Slot] {
        switch session {
        case .upperHeavy:
            return [s("Bench Press", "bench_press", .main),
                    s("Barbell Row", "barbell_row", .main),
                    s("Overhead Press", "overhead_press", .secondary),
                    s("Pull-Up", "pull_up", .secondary),
                    s("Skull Crusher", "skull_crusher", .accessory),
                    s("Barbell Curl", "barbell_curl", .accessory)]
        case .upperMedium:
            return [s("Overhead Press", "overhead_press", .main),
                    s("Pull-Up", "pull_up", .main),
                    s("Incline Dumbbell Press", "incline_dumbbell_press", .secondary),
                    s("Single-Arm Dumbbell Row", "dumbbell_row", .secondary),
                    s("Tricep Dip", "tricep_dip", .accessory),
                    s("Hammer Curl", "hammer_curl", .accessory)]
        case .upperLight:
            return [s("Incline Dumbbell Press", "incline_dumbbell_press", .main),
                    s("Lat Pulldown", "lat_pulldown", .main),
                    s("Single-Arm Dumbbell Row", "dumbbell_row", .secondary),
                    s("Lateral Raise", "lateral_raise", .accessory),
                    s("Cable Fly", "cable_fly", .accessory),
                    s("Hammer Curl", "hammer_curl", .accessory)]
        case .lowerHeavy:
            return [s("Back Squat", "squat", .main),
                    s("Romanian Deadlift", "romanian_deadlift", .secondary),
                    s("Barbell Hip Thrust", "hip_thrust", .secondary),
                    s("Walking Lunge", "walking_lunge", .accessory),
                    s("Hanging Leg Raise", "leg_raise", .core)]
        case .lowerMedium:
            return [s("Deadlift", "deadlift", .main),
                    s("Goblet Squat", "goblet_squat", .secondary),
                    s("Walking Lunge", "walking_lunge", .accessory),
                    s("Russian Twist", "russian_twist", .core)]
        case .lowerLight:
            return [s("Goblet Squat", "goblet_squat", .main),
                    s("Barbell Hip Thrust", "hip_thrust", .main),
                    s("Walking Lunge", "walking_lunge", .secondary),
                    s("Glute Bridge", "glute_bridge", .accessory),
                    s("Plank", "plank", .timed)]
        case .fullHeavy:
            return [s("Back Squat", "squat", .main),
                    s("Bench Press", "bench_press", .main),
                    s("Barbell Row", "barbell_row", .secondary),
                    s("Overhead Press", "overhead_press", .accessory),
                    s("Plank", "plank", .timed)]
        case .fullMedium:
            return [s("Deadlift", "deadlift", .main),
                    s("Incline Dumbbell Press", "incline_dumbbell_press", .secondary),
                    s("Pull-Up", "pull_up", .secondary),
                    s("Walking Lunge", "walking_lunge", .accessory),
                    s("Russian Twist", "russian_twist", .core)]
        case .fullLight:
            return [s("Goblet Squat", "goblet_squat", .main),
                    s("Push-Up", "push_up", .secondary),
                    s("Single-Arm Dumbbell Row", "dumbbell_row", .secondary),
                    s("Glute Bridge", "glute_bridge", .accessory),
                    s("Hanging Leg Raise", "leg_raise", .core)]
        case .conditioning:
            return [s("Jump Rope", "jump_rope", .timed),
                    s("Goblet Squat", "goblet_squat", .accessory),
                    s("Push-Up", "push_up", .accessory),
                    s("Mountain Climber", "mountain_climber", .timed),
                    s("Walking Lunge", "walking_lunge", .accessory),
                    s("Plank", "plank", .timed)]
        }
    }

    /// Beginners skip the most technical barbell lifts until they have a base.
    private static func beginnerSwap(_ slot: Slot) -> Slot {
        switch slot.id {
        case "squat":         return s("Goblet Squat", "goblet_squat", slot.role)
        case "deadlift":      return s("Romanian Deadlift", "romanian_deadlift", slot.role)
        case "barbell_row":   return s("Single-Arm Dumbbell Row", "dumbbell_row", slot.role)
        case "pull_up":       return s("Lat Pulldown", "lat_pulldown", slot.role)
        case "skull_crusher": return s("Tricep Dip", "tricep_dip", slot.role)
        case "leg_raise":     return s("Crunch", "crunch", slot.role)
        default:              return slot
        }
    }

    // MARK: - Sets and reps

    /// Sets and reps for one exercise. Heavy days: few reps, more sets. Light
    /// days: more reps, fewer sets. Deload: fewer of everything.
    static func scheme(for slot: Slot, intensity: DayIntensity, beginner: Bool,
                       volume: CoachReport.VolumeDecision, circuit: Bool) -> (Int, String) {
        if slot.role == .timed {
            if slot.id == "jump_rope" { return (intensity == .deload ? 3 : 4, "1 min") }
            let secs: Int
            switch intensity {
            case .heavy:          secs = 60
            case .medium:         secs = 45
            case .light, .rest, .sport: secs = circuit ? 40 : 30
            case .deload:         secs = 30
            }
            return (intensity == .deload ? 2 : 3, "\(secs) sec")
        }
        if circuit { return (3, "15") }

        var sets = 3, reps = 12
        switch (intensity, slot.role) {
        case (.heavy, .main):       (sets, reps) = beginner ? (4, 6) : (5, 5)
        case (.heavy, .secondary):  (sets, reps) = beginner ? (3, 8) : (4, 6)
        case (.heavy, _):           (sets, reps) = (3, 10)
        case (.medium, .main):      (sets, reps) = (4, 8)
        case (.medium, .secondary): (sets, reps) = (3, 10)
        case (.medium, _):          (sets, reps) = (3, 12)
        case (.deload, .main):      (sets, reps) = (3, 5)
        case (.deload, _):          (sets, reps) = (2, 10)
        case (_, .main),
             (_, .secondary):       (sets, reps) = (3, 12)
        default:                    (sets, reps) = (2, 15)
        }
        if slot.role == .core { (sets, reps) = (3, intensity == .heavy ? 12 : 15) }
        if volume == .increased && slot.role == .main { sets += 1 }
        if volume == .reduced && (slot.role == .accessory || slot.role == .core) { sets = max(2, sets - 1) }
        return (sets, "\(reps)")
    }

    // MARK: - Loads

    /// Kilos for a weighted lift, from the best set the user did in the last
    /// six weeks. Without history, an effort target (RPE) instead of a guess.
    static func load(for slot: Slot, reps: Int, intensity: DayIntensity,
                     sessions: [WorkoutSession], now: Date) -> String? {
        guard let id = slot.id, reps > 0,
              slot.role != .timed, slot.role != .core,
              let equipment = ExerciseDatabase.all.first(where: { $0.id == id })?.equipment,
              [.barbell, .dumbbell, .cable, .machine, .kettlebell].contains(equipment)
        else { return nil }

        let window = sessions.filter { $0.startedAt >= now.addingTimeInterval(-42 * 86_400) }
        let step: Double = equipment == .dumbbell ? 2 : 2.5
        func kgText(_ kg: Double) -> String { " · " + String(format: "%g", kg) + " kg" }

        // Same rep range as last time on a hard day: follow linear progression
        // — every set done means more weight. Estimating from the one-rep max
        // alone backs off a little and suggested *less* than last week.
        if intensity == .heavy || intensity == .medium,
           let last = window.lazy.compactMap({ $0.exercises.first { $0.exerciseID == id } }).first,
           let lastReps = last.sets.first?.reps, abs(lastReps - reps) <= 2 {
            let next = ProgressionEngine.suggestion(for: id, history: window, targetReps: reps,
                                                    fallbackWeight: 0)
            if next.weight > 0 { return kgText(next.weight) }
        }

        // Epley estimate of the one-rep max; capped at 12 reps where it stops
        // being reliable.
        let e1rm = window
            .flatMap { $0.exercises.filter { $0.exerciseID == id } }
            .flatMap(\.sets)
            .filter { $0.completed && $0.weight > 0 && $0.reps > 0 }
            .map { $0.weight * (1 + Double(min($0.reps, 12)) / 30) }
            .max()

        guard let e1rm else {
            let rpe: Int
            switch intensity {
            case .heavy:  rpe = 8
            case .medium: rpe = 7
            case .light:  rpe = 6
            default:      rpe = 5
            }
            return " · RPE \(rpe)"
        }

        // Weight you could lift for `reps` at maximum effort, then backed off
        // so a heavy day leaves ~2 reps in the tank and a light day ~4.
        let factor: Double
        switch intensity {
        case .heavy:  factor = 0.95
        case .medium: factor = 0.90
        case .light:  factor = 0.85
        default:      factor = 0.75
        }
        var kg = e1rm / (1 + Double(reps) / 30) * factor
        if ProgressionEngine.suggestion(for: id, history: window, targetReps: reps,
                                        fallbackWeight: 0).reason == .deload {
            kg *= 0.9
        }
        kg = max(step, (kg / step).rounded() * step)
        return kgText(kg)
    }

    // MARK: - Sport

    /// Turns the lightest training day into strength work for the user's
    /// sport, so gym and sport complement each other instead of competing.
    private static func applySportSupport(_ week: inout Week, sportID: String) {
        let family = SportFamily.forSport(id: sportID)
        let sportName = NSLocalizedString(SportLibrary.byID(sportID)?.nameKey ?? sportID, comment: "")
        // Prefer a gym day that isn't also a practice day: six grip and neck
        // exercises on top of a class would defeat the point.
        let workouts = week.days.indices.filter { week.days[$0].isWorkout }
        let free = workouts.filter { !week.days[$0].isSportDay }
        let candidates = free.isEmpty ? workouts : free
        guard let idx = candidates.first(where: { week.days[$0].intensity == .light })
                ?? candidates.first(where: { week.days[$0].intensity == .medium })
                ?? candidates.last else { return }
        week.days[idx].focus = String(format: LocalCoachService.supportFocusFormat(), sportName)
        week.days[idx].exercises = LocalCoachService.supportExercises(family)
        if week.days[idx].intensity != .deload { week.days[idx].intensity = .light }
        week.loads[idx] = [:]
    }

    private static func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
}
