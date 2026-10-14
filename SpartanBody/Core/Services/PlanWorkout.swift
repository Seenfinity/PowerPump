import Foundation

/// Turns a day of the coach's plan into a workout that can be started.
///
/// Plan days list lines like "Bench Press 4×8" or "Plank 3×60 sec · RPE 8",
/// always in English. Exercises from the library keep their id (so weights,
/// records and progression follow them); the rest use their English name as
/// id, which the workout screen translates.
enum PlanWorkout {
    static func template(for day: DayPlan) -> WorkoutTemplate {
        var seen = Set<String>()
        let pattern = try! NSRegularExpression(pattern: #"^(.*?)\s+(\d+)\s*[×x]\s*(\d+)"#)
        let exercises = day.exercises.compactMap { line -> TemplateExercise? in
            let text = line.components(separatedBy: " · ").first ?? line
            guard let m = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let nr = Range(m.range(at: 1), in: text), let sr = Range(m.range(at: 2), in: text),
                  let rr = Range(m.range(at: 3), in: text), let sets = Int(text[sr]) else { return nil }
            let name = String(text[nr]).trimmingCharacters(in: .whitespaces)
            let id = ExerciseDatabase.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id ?? name
            // The same exercise twice in one day is done once.
            guard seen.insert(id).inserted else { return nil }
            return TemplateExercise(exerciseID: id, sets: sets, targetReps: String(text[rr]), targetWeight: 0)
        }
        return WorkoutTemplate(name: day.focus, exercises: exercises)
    }

    /// A rough length: about two and a half minutes per set, plus warm-up.
    static func minutes(for template: WorkoutTemplate) -> Int {
        let sets = template.exercises.reduce(0) { $0 + $1.sets }
        return max(15, Int((Double(sets) * 2.5 + 5) / 5) * 5)
    }
}
