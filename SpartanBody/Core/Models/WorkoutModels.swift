import Foundation

struct WorkoutTemplate: Identifiable, Codable {
    var id: UUID = .init()
    var name: String
    var exercises: [TemplateExercise]
    var createdAt: Date = .now
}

struct TemplateExercise: Identifiable, Codable {
    var id: UUID = .init()
    var exerciseID: String
    var sets: Int
    var targetReps: String
    var targetWeight: Double
}

struct WorkoutSession: Identifiable, Codable {
    var id: UUID = .init()
    var name: String
    var startedAt: Date = .now
    var finishedAt: Date?
    var exercises: [SessionExercise]
    /// How hard the session felt, 1–10, asked by Spartan after it. nil when
    /// not answered (and for sessions saved before it existed).
    var rpe: Int? = nil

    var duration: TimeInterval { (finishedAt ?? .now).timeIntervalSince(startedAt) }
    var completedSets: Int { exercises.flatMap(\.sets).filter(\.completed).count }
    var totalVolume: Double {
        exercises.flatMap(\.sets).filter(\.completed)
            .reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

struct SessionExercise: Identifiable, Codable {
    var id: UUID = .init()
    var exerciseID: String
    var sets: [SessionSet]

    var completedSetCount: Int { sets.filter(\.completed).count }
}

struct SessionSet: Identifiable, Codable {
    var id: UUID = .init()
    var setNumber: Int
    var weight: Double
    var reps: Int
    var completed: Bool = false
}
