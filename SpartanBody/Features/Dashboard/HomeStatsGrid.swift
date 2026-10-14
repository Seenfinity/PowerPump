import SwiftUI

/// The three summary tiles under the calorie card: weight, streak, water.
///
/// These numbers used to be spread down the page — weight only in Progress,
/// streak only in Progress, water in a full-width row of its own. Grouping them
/// means you see all three without scrolling.
struct HomeStatsGrid: View {
    @ObservedObject private var profile  = UserProfile.shared
    @ObservedObject private var progress = ProgressStore.shared
    @ObservedObject private var workouts = WorkoutStore.shared
    @ObservedObject private var water    = WaterStore.shared
    @ObservedObject private var health   = HealthKitService.shared

    let onTapWeight: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                weightTile
                streakTile
            }
            HStack(spacing: 12) {
                waterTile
                sleepTile
            }
        }
    }

    // MARK: - Weight

    private var recentWeights: [Double] {
        progress.weightEntries.suffix(8).map(\.weightKg)
    }

    private var weightTile: some View {
        Button(action: onTapWeight) {
            StatTile(label: "Weight") {
                // Before the first weigh-in, show the weight from onboarding
                // rather than a dash — the number always exists, and an empty
                // tile makes the grid look broken on day one.
                TileValue(value: String(format: "%.1f",
                                        progress.weightEntries.last?.weightKg ?? profile.weightKg),
                          unit: "kg")
                if recentWeights.count >= 2 {
                    Sparkline(values: recentWeights)
                        .frame(height: 30)
                        .padding(.top, 8)
                } else {
                    Text("Log Weight")
                        .font(SBFont.label(11))
                        .foregroundColor(.sbAccent)
                        .padding(.top, 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak

    private var streakTile: some View {
        StatTile(label: "Streak") {
            TileValue(value: "\(workouts.currentStreak)",
                      unit: Self.dayUnit(workouts.currentStreak))
            VStack(alignment: .leading, spacing: 1) {
                Text("Your best streak")
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
                Text(verbatim: String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: ""),
                                      workouts.longestStreak))
                    .font(SBFont.label(11))
                    .foregroundColor(.sbTextPrimary)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Water

    /// Tap anywhere on the tile to log a glass — still one tap, like the old
    /// row of eight drops. The small minus undoes a mis-tap, which is why it
    /// exists rather than making the tile cycle back round to zero.
    private var waterTile: some View {
        Button {
            HapticManager.light()
            water.set(min(water.todayGlasses + 1, 8))
        } label: {
            StatTile(label: "Water Intake") {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    TileValue(value: "\(water.todayGlasses)", unit: "/ 8")
                    Spacer(minLength: 0)
                    if water.todayGlasses > 0 {
                        Button {
                            HapticManager.light()
                            water.set(water.todayGlasses - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.sbCyan)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.sbCyan.opacity(0.15)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.sbSurfaceRaised)
                        Capsule().fill(Color.sbCyan)
                            .frame(width: geo.size.width * CGFloat(water.todayGlasses) / 8)
                    }
                }
                .frame(height: 6)
                .padding(.top, 12)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: water.todayGlasses)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sleep

    /// Last night from Apple Health. Most people have no sleep data unless they
    /// wear a watch, so the empty state says why instead of showing "0h".
    private var sleepTile: some View {
        StatTile(label: "Sleep") {
            if health.sleepLastNight > 0 {
                let total = Int(health.sleepLastNight) / 60
                TileValue(value: "\(total / 60)", unit: "h \(total % 60)m")
                Text(sleepVerdict)
                    .font(SBFont.label(11))
                    .foregroundColor(health.sleepLastNight >= 7 * 3600 ? .sbGreen : .orange)
                    .padding(.top, 10)
            } else {
                // A big em dash reads as a stray bar at display weight, so the
                // empty state uses a dimmed moon instead.
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(Color.sbTextSecondary.opacity(0.45))
                    .padding(.top, 8)
                Text(health.isAuthorized ? "No sleep recorded" : "Connect Apple Health")
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
        }
    }

    /// "día"/"días", "jour"/"jours"… by each language's plural rule (French
    /// says "0 jour"). The number is formatted separately in the tile.
    static func dayUnit(_ n: Int) -> String {
        let full = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: ""), n)
        return full.replacingOccurrences(of: "\(n)", with: "").trimmingCharacters(in: .whitespaces)
    }

    private var sleepVerdict: LocalizedStringKey {
        health.sleepLastNight >= 7 * 3600 ? "Good rest" : "Short night"
    }
}

// MARK: - Pieces

private struct StatTile<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey(label))
                .font(SBFont.label(10))
                .foregroundColor(.sbTextSecondary)
                .textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }
}

private struct TileValue: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: value)
                .font(SBFont.display(24))
                .foregroundColor(.sbTextPrimary)
                .monospacedDigit()
            Text(verbatim: unit)
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary)
        }
        .padding(.top, 6)
    }
}

/// Bar chart of the last few weigh-ins, scaled to their own range so small
/// changes are still visible.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let span = max(hi - lo, 0.1)          // never divide by zero
            let count = max(values.count, 1)
            let gap: CGFloat = 3
            let barWidth = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 2)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    let ratio = (v - lo) / span
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.sbAccent.opacity(0.75))
                        // Floor at 25% so a flat week still reads as a chart.
                        .frame(width: barWidth,
                               height: max(geo.size.height * (0.25 + 0.75 * ratio), 3))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
