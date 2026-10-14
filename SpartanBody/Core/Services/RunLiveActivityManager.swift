import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// Drives the run/walk/hike Live Activity (Dynamic Island + Lock Screen).
// Called from RunStore on start/pause/resume/finish/discard and on every
// location update so distance and pace stay in sync while the app is in
// background.
final class RunLiveActivityManager {
    static let shared = RunLiveActivityManager()
    private init() {}

    func sync(session: RunSession?, isPaused: Bool) {
        guard #available(iOS 16.1, *) else { return }
        if let session {
            updateOrStart(session: session, isPaused: isPaused)
        } else {
            endAll()
        }
    }

    @available(iOS 16.1, *)
    private func updateOrStart(session: RunSession, isPaused: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = RunActivityAttributes.ContentState(
            distanceMeters:   session.distanceMeters,
            movingSeconds:    session.movingSeconds,
            paceSecondsPerKm: session.paceSecondsPerKm,
            calories:         session.calories,
            isPaused:         isPaused
        )

        if let activity = Activity<RunActivityAttributes>.activities.first {
            Task { await activity.update(using: state) }
        } else {
            let attributes = RunActivityAttributes(
                activityRaw: session.activity.rawValue,
                startedAt:   session.startedAt
            )
            _ = try? Activity.request(attributes: attributes, contentState: state)
        }
    }

    @available(iOS 16.1, *)
    private func endAll() {
        Task {
            for activity in Activity<RunActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
