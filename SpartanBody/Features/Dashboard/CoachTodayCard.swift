import SwiftUI

/// The coach's card on the dashboard.
///
/// Before, this always read "get your free 7-day plan" — useful on day one and
/// useless every day after. Now it answers the question the user actually opens
/// the app with: *what am I doing today?*
struct CoachTodayCard: View {
    @ObservedObject private var planStore = PlanStore.shared
    let action: () -> Void

    private var today: DayPlan? { planStore.todayPlan }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                SBPhoto(name: CoachPhoto.name(for: today))
                    .frame(height: 150)

                // Keeps the text readable whatever the photo does underneath.
                LinearGradient(
                    colors: [.black.opacity(0.88), .black.opacity(0.35), .black.opacity(0.1)],
                    startPoint: .bottom, endPoint: .top)

                content
                    .padding(16)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.sbAccent.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let today {
            VStack(alignment: .leading, spacing: 9) {
                Text(today.focus)
                    .font(SBFont.display(19))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 1)

                HStack(spacing: 6) {
                    pill(Text("Today"), highlighted: true)
                    if today.isWorkout, let intensity = today.intensity {
                        pill(Text(LocalizedStringKey(intensity.labelKey)))
                    }
                    if today.isWorkout {
                        pill(Text("\(today.exercises.count) exercises"))
                    } else if today.intensity == .sport {
                        pill(Text(LocalizedStringKey(DayIntensity.sport.labelKey)))
                    } else {
                        pill(Text("Rest Day"))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI Coach")
                    .font(SBFont.display(19))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 1)
                Text("Get your personalised free 7-day plan")
                    .font(SBFont.caption())
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }

    private func pill(_ label: Text, highlighted: Bool = false) -> some View {
        label
            .font(SBFont.label(10))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(highlighted ? Color.sbAccent : Color.white.opacity(0.18)))
            .overlay(
                Capsule().stroke(highlighted ? .clear : Color.white.opacity(0.25)))
    }
}

/// Picks the photo that matches the day's training.
///
/// Matching happens on the exercise names, which `LocalCoachService` always
/// writes in English regardless of the user's language — unlike `focus`, which
/// is translated at generation time and so can't be matched on.
enum CoachPhoto {
    static func name(for day: DayPlan?) -> String {
        guard let day else { return "photo_general" }
        // Practice day: the sport's own photo (yoga, or its category's).
        if day.intensity == .sport, let id = day.sport, let sport = SportLibrary.byID(id) {
            return sport.photoName
        }
        guard day.isWorkout else { return "photo_cardio" }

        let text = day.exercises.joined(separator: " ").lowercased()

        if text.contains("deadlift")                          { return "photo_deadlift" }
        if contains(text, "squat", "lunge", "leg", "calf", "hip thrust", "glute") {
            return "photo_legs"
        }
        if contains(text, "pull-up", "pull up", "row", "pulldown", "curl", "chin") {
            return "photo_pull"
        }
        if contains(text, "bench", "press", "push-up", "push up", "dip", "fly") {
            return "photo_push"
        }
        if contains(text, "run", "jump rope", "sprint", "mountain climber", "burpee", "cycling") {
            return "photo_cardio"
        }
        return "photo_general"
    }

    private static func contains(_ text: String, _ needles: String...) -> Bool {
        needles.contains { text.contains($0) }
    }
}
