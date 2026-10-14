import Foundation

/// Exercises with a live form check from the camera. The analysis itself is
/// LiveFormTracker, the same engine as the video form check.
enum SupportedExercise: String, CaseIterable, Identifiable {
    case squat          = "squat"
    case pushUp         = "push_up"
    case deadlift       = "deadlift"
    case overheadPress  = "overhead_press"
    case plank          = "plank"
    case bicepCurl      = "barbell_curl"

    var id: String { rawValue }

    var videoExercise: VideoExercise {
        switch self {
        case .squat:         return .squat
        case .pushUp:        return .pushUp
        case .deadlift:      return .deadlift
        case .overheadPress: return .overheadPress
        case .plank:         return .plank
        case .bicepCurl:     return .bicepCurl
        }
    }

    var nameKey: String { videoExercise.nameKey }
    var cameraKey: String { videoExercise.cameraKey }
    var icon: String { videoExercise.icon }
}
