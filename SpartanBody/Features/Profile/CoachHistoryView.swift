import SwiftUI

// MARK: - Shared bits

extension WeeklyReview {
    /// "15–21 sep" in the app's language.
    var rangeText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.setLocalizedDateFormatFromTemplate("d MMM")
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let day = Calendar.current.component(.day, from: weekStart)
        let sameMonth = Calendar.current.isDate(weekStart, equalTo: end, toGranularity: .month)
        return sameMonth ? "\(day)-\(f.string(from: end))" : "\(f.string(from: weekStart)) - \(f.string(from: end))"
    }
}

/// 0–100 ring: green from 80, orange from 55, red below.
struct ReviewScoreRing: View {
    let score: Int
    var size: CGFloat = 46
    var line: CGFloat = 5

    static func color(_ s: Int) -> Color { s >= 80 ? .sbGreen : s >= 55 ? .orange : .sbRed }

    var body: some View {
        ZStack {
            Circle().stroke(Color.sbSurfaceRaised, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Self.color(score), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(score)")
                .font(SBFont.heading(size * 0.34))
                .foregroundColor(.sbTextPrimary)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - List

/// Week-by-week history of what the coach saw and what it asked you to focus on.
struct CoachHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CoachHistoryStore.shared
    @ObservedObject private var health = HealthKitService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("review.subtitle")
                            .font(SBFont.caption())
                            .foregroundColor(.sbTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if store.reviews.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(store.reviews.enumerated()), id: \.element.id) { i, r in
                                NavigationLink {
                                    WeekReviewView(review: r,
                                                   previous: i + 1 < store.reviews.count ? store.reviews[i + 1] : nil)
                                } label: {
                                    row(r, latest: i == 0)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !health.isAuthorized && health.isAvailable {
                            healthHint
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(Text("review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.sbAccent)
                }
            }
            .onAppear {
                // Already connected users get asked only for the new types
                // (resting heart rate, HRV); iOS skips what's already granted.
                if health.isAuthorized {
                    health.requestAuthorization { _ in store.refresh() }
                } else {
                    store.refresh()
                }
            }
        }
    }

    private func row(_ r: WeeklyReview, latest: Bool) -> some View {
        HStack(spacing: 14) {
            ReviewScoreRing(score: r.score)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: r.rangeText)
                        .font(SBFont.heading(15))
                        .foregroundColor(.sbTextPrimary)
                    if latest {
                        Text("review.lastWeek")
                            .font(SBFont.label(9))
                            .foregroundColor(.sbAccent)
                            .textCase(.uppercase)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.sbAccentDim))
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: r.focus?.icon ?? "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(LocalizedStringKey(r.focus.map { "review.focusOn.\($0.rawValue)" } ?? "review.roundWeek"))
                        .font(SBFont.caption())
                }
                .foregroundColor(r.focus == nil ? .sbGreen : .sbTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.sbTextSecondary.opacity(0.5))
        }
        .padding(14)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(latest ? Color.sbAccent.opacity(0.4) : Color.sbBorder))
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.sbAccent)
            Text("review.empty")
                .font(SBFont.body())
                .foregroundColor(.sbTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.sbSurface)
        .cornerRadius(16)
    }

    private var healthHint: some View {
        Button { health.requestAuthorization { _ in store.refresh() } } label: {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").foregroundColor(.sbRed)
                Text("review.connectHealth")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.sbTextSecondary)
            }
            .padding(12)
            .background(Color.sbSurface)
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

struct WeekReviewView: View {
    let review: WeeklyReview
    let previous: WeeklyReview?

    var body: some View {
        ZStack {
            Color.sbBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    focusCard
                    areasCard
                    statsGrid
                    if let notes = review.coachNotes, !notes.isEmpty { decisions(notes) }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle(Text(verbatim: review.rangeText))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ReviewScoreRing(score: review.score, size: 76, line: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text("review.weekScore")
                    .font(SBFont.label(11))
                    .foregroundColor(.sbTextSecondary)
                    .textCase(.uppercase)
                if let previous {
                    let d = review.score - previous.score
                    HStack(spacing: 4) {
                        Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(verbatim: String(format: NSLocalizedString("review.vsLast", comment: ""),
                                              d >= 0 ? "+\(d)" : "\(d)"))
                    }
                    .font(SBFont.caption())
                    .foregroundColor(d >= 0 ? .sbGreen : .orange)
                }
            }
            Spacer()
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: review.focus?.icon ?? "checkmark.seal.fill")
                Text(LocalizedStringKey(review.focus == nil ? "review.roundWeek" : "review.focusTitle"))
                    .textCase(.uppercase)
            }
            .font(SBFont.label(11))
            .foregroundColor(.white.opacity(0.9))
            Text(verbatim: WeeklyReviewEngine.focusText(review))
                .font(SBFont.body())
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(review.focus == nil ? Color.sbGreen : Color.sbAccent))
    }

    private var areasCard: some View {
        VStack(spacing: 12) {
            ForEach(ReviewArea.allCases, id: \.self) { area in
                if let s = review.score(area) { areaRow(area, s) }
            }
        }
        .padding(16)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    private func areaRow(_ area: ReviewArea, _ s: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: area.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(area == review.focus ? .sbAccent : .sbTextSecondary)
                    .frame(width: 18)
                Text(LocalizedStringKey(area.labelKey))
                    .font(SBFont.body(15))
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                Text(verbatim: value(area))
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .monospacedDigit()
                if let p = previous?.score(area), p != s {
                    Image(systemName: s > p ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(s > p ? .sbGreen : .orange)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sbSurfaceRaised)
                    Capsule().fill(ReviewScoreRing.color(s))
                        .frame(width: geo.size.width * CGFloat(s) / 100)
                }
            }
            .frame(height: 6)
        }
    }

    /// The number behind each bar.
    private func value(_ a: ReviewArea) -> String {
        let r = review
        switch a {
        case .training: return "\(r.workoutsDone)/\(r.workoutsPlanned)"
        case .protein:  return "\(r.avgProtein ?? 0)/\(r.proteinTarget) g"
        case .sleep:
            let h = r.avgSleep ?? 0
            return String(format: "%d h %02d", Int(h), Int((h - Double(Int(h))) * 60))
        case .activity: return String(format: NSLocalizedString("review.steps", comment: ""), r.avgSteps ?? 0)
        case .logging:  return String(format: NSLocalizedString("review.days", comment: ""), r.loggedDays)
        case .recovery:
            return String(format: "%.0f bpm · %.0f ms", r.restingHR ?? 0, r.hrv ?? 0)
        }
    }

    private var statsGrid: some View {
        let r = review
        var items: [(String, String, String)] = [
            ("dumbbell.fill", "Workouts", "\(r.workoutsDone)/\(r.workoutsPlanned)"),
        ]
        if r.sportSessions > 0 {
            items.append(("figure.martial.arts", "review.sportSessions", "\(r.sportSessions)"))
        }
        if let w = r.weightChange {
            items.append(("scalemass.fill", "Weight", String(format: "%+.1f kg", w)))
        }
        if let k = r.avgCalories {
            items.append(("flame.fill", "coach.ui.avgIntake", "\(k) kcal"))
        }
        if let rhr = r.restingHR {
            let base = r.restingHRBaseline.map { String(format: " (%+.0f)", rhr - $0) } ?? ""
            items.append(("heart.fill", "review.restingHR", String(format: "%.0f bpm", rhr) + base))
        }
        if let hrv = r.hrv {
            let base = r.hrvBaseline.map { String(format: " (%+.0f%%)", (hrv - $0) / $0 * 100) } ?? ""
            items.append(("waveform.path.ecg", "review.hrv", String(format: "%.0f ms", hrv) + base))
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                         spacing: 10) {
            ForEach(items, id: \.1) { icon, label, value in
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.sbAccent)
                    Text(verbatim: value)
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(LocalizedStringKey(label))
                        .font(SBFont.label(10))
                        .foregroundColor(.sbTextSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.sbSurface)
                .cornerRadius(12)
            }
        }
    }

    private func decisions(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("review.coachDecided")
                .font(SBFont.heading(16))
                .foregroundColor(.sbTextPrimary)
            ForEach(notes, id: \.self) { n in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.sbAccent)
                        .padding(.top, 4)
                    Text(verbatim: n)
                        .font(SBFont.body(14))
                        .foregroundColor(.sbTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbSurface)
        .cornerRadius(16)
    }
}

// MARK: - Profile card

/// Latest week at a glance, opening the full history.
struct CoachHistoryCard: View {
    @ObservedObject private var store = CoachHistoryStore.shared
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let r = store.reviews.first {
                    ReviewScoreRing(score: r.score, size: 52, line: 6)
                } else {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.sbAccent)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.sbAccentDim))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("review.title")
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                    if let r = store.reviews.first {
                        Text(LocalizedStringKey(r.focus.map { "review.focusOn.\($0.rawValue)" } ?? "review.roundWeek"))
                            .font(SBFont.caption())
                            .foregroundColor(r.focus == nil ? .sbGreen : .sbAccent)
                        Text(verbatim: r.rangeText)
                            .font(SBFont.label(10))
                            .foregroundColor(.sbTextSecondary)
                    } else {
                        Text("review.emptyShort")
                            .font(SBFont.caption())
                            .foregroundColor(.sbTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.sbTextSecondary.opacity(0.5))
            }
            .padding(16)
            .background(Color.sbSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
