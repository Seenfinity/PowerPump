import SwiftUI

struct ProfileView: View {
    @ObservedObject private var profile  = UserProfile.shared
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var health   = HealthKitService.shared
    @ObservedObject private var workouts = WorkoutStore.shared
    @ObservedObject private var runs     = RunStore.shared
    @ObservedObject private var foodLog  = FoodLogStore.shared
    @ObservedObject private var progress = ProgressStore.shared

    @State private var showSettings     = false
    @State private var showRMCalculator = false
    @State private var showMyData       = false
    @State private var showAchievements = false
    @State private var showHistory      = false
    @State private var showAbout        = false
    @State private var showPrivacy      = false
    @State private var showSources      = false
    /// Sport days when the screen opened, to notice a change on leaving.
    @State private var weekdaysOnAppear: [Int] = []

    var body: some View {
        NavigationView {
            ZStack {
                Color.sbBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        header
                        quickCards
                        CoachHistoryCard { showHistory = true }
                        statsRow
                        goalsSection
                        healthSection
                        otherSection
                        SBSecondaryButton(title: "Edit Profile") {
                            profile.onboardingDone = false
                        }
                        // The tab bar floats over the scroll view, so the last
                        // row needs room or it sits underneath it.
                        Spacer(minLength: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if health.isAuthorized { health.fetchTodayStats() }
                weekdaysOnAppear = profile.sportWeekdays
                CoachHistoryStore.shared.refresh()
            }
            // New sport days reshape the week (where the heavy days go, which
            // days get more carbs), so rebuild the plan now rather than at the
            // end of the week. Done on leaving, not per tap, so picking three
            // days builds one plan, not three.
            .onDisappear {
                // onDisappear can fire more than once per exit; resetting the
                // baseline makes the rebuild happen exactly once.
                if profile.sportWeekdays != weekdaysOnAppear, PlanStore.shared.plan != nil {
                    weekdaysOnAppear = profile.sportWeekdays
                    PlanStore.shared.generate(inputs: .current())
                }
            }
        }
        .sheet(isPresented: $showSettings)     { SettingsView() }
        .sheet(isPresented: $showRMCalculator) { RMCalculatorView() }
        .sheet(isPresented: $showMyData)       { MyDataSheet() }
        .sheet(isPresented: $showAchievements) { AchievementsSheet() }
        .sheet(isPresented: $showHistory)      { CoachHistoryView() }
        .sheet(isPresented: $showAbout)        { AboutView() }
        .sheet(isPresented: $showPrivacy)      { PrivacyPolicyView() }
        .sheet(isPresented: $showSources)      { SourcesView() }
    }

    // MARK: - Header

    /// What the tag under the name says: the sport being trained if there is
    /// one, otherwise the goal — so the tag is never empty.
    private var headerTag: String {
        let ids = profile.practicedSportIDs
        guard !ids.isEmpty else { return profile.goal.rawValue }
        // Name the first sport rather than just counting them — "Jiu-Jitsu +1"
        // tells you more at a glance than "2 sports".
        guard let first = ids.compactMap({ SportLibrary.byID($0) }).first else {
            return profile.goal.rawValue
        }
        let name = ids.count == 1 ? PT(first.nameKey) : "\(PT(first.nameKey)) +\(ids.count - 1)"
        guard profile.sportDaysPerWeek > 0 else { return name }
        let days = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: ""), profile.sportDaysPerWeek)
        return "\(name) · \(days)"
    }

    private var displayName: String {
        profile.name.isEmpty ? "Spartan" : profile.name
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(LinearGradient.sbAccentGradient, lineWidth: 3)
                    .frame(width: 70, height: 70)
                Circle().fill(Color.sbAccentDim).frame(width: 60, height: 60)
                Text(String(displayName.prefix(1)).uppercased())
                    .font(SBFont.display(26))
                    .foregroundColor(.sbAccent)
            }
            .shadow(color: Color.sbAccent.opacity(0.25), radius: 10)

            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: displayName)
                    .font(SBFont.display(24))
                    .foregroundColor(.sbTextPrimary)
                    .lineLimit(1)
                SBTag(text: headerTag)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: - Quick cards

    private var unlockedCount: Int {
        workouts.unlockedAchievements(
            foodLogHasEntries: !foodLog.todayEntries.isEmpty,
            weightLogged: !progress.weightEntries.isEmpty
        ).count
    }

    private var quickCards: some View {
        HStack(spacing: 10) {
            ProfileQuickCard(
                icon: "trophy.fill", tint: .orange,
                title: "My Achievements",
                value: "\(unlockedCount)/\(Achievement.allCases.count)"
            ) {
                showAchievements = true
            }

            ProfileQuickCard(
                icon: "chart.bar.fill", tint: .sbAccent,
                title: "My Data",
                value: NSLocalizedString("View all", comment: "")
            ) {
                showMyData = true
            }

            ProfileQuickCard(
                icon: "map.fill", tint: .sbCyan,
                title: "My Routes",
                value: String.localizedStringWithFormat(NSLocalizedString("%lld runs", comment: ""), runs.history.count)
            ) {
                WorkoutRouter.pendingTab = .run
                NotificationCenter.default.post(name: .switchToTab, object: 1)
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        SBCard {
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    SBStatBox(value: String(format: "%.1f", locale: .current, profile.weightKg), label: "Weight", unit: "kg")
                        .frame(maxWidth: .infinity)
                    Divider().frame(height: 40)
                    SBStatBox(value: "\(Int(profile.heightCm))", label: "Height", unit: "cm")
                        .frame(maxWidth: .infinity)
                    Divider().frame(height: 40)
                    SBStatBox(value: String(format: "%.1f", profile.bmi), label: "IMC", unit: "")
                        .frame(maxWidth: .infinity)
                }
                HStack {
                    Text("BMI Category").font(SBFont.caption()).foregroundColor(.sbTextSecondary)
                    Spacer()
                    SBTag(text: profile.bmiCategory,
                          color: profile.bmi < 18.5 || profile.bmi >= 25 ? .sbRed : .sbGreen)
                }
            }
        }
    }

    // MARK: - My goals

    private var goalsSection: some View {
        ProfileSection(title: "My Goals") {
            ProfileRow(icon: "flame.fill", tint: .orange, label: "Calories",
                       value: "\(profile.dailyCalorieTarget) kcal")
            ProfileDivider()
            ProfileRow(icon: "fish.fill", tint: .sbAccent, label: "Protein",
                       value: "\(profile.dailyProteinTarget) g")
            ProfileDivider()
            // The raw value is the English key — show it translated, or the
            // row reads "Lightly Active" in the middle of a Spanish screen.
            ProfileRow(icon: "figure.walk", tint: .sbGreen, label: "Activity",
                       value: NSLocalizedString(profile.activityLevel.rawValue, comment: ""))
            ProfileDivider()
            sportRow
            if !profile.practicedSportIDs.isEmpty {
                selectedSportsRow
                ProfileDivider()
                daysRow
            }
        }
    }

    /// Sports practised outside the gym. Kept editable here so users who
    /// finished onboarding before this existed can still set them. Multiple
    /// sports allowed — the menu toggles each on and off.
    private var sportRow: some View {
        HStack(spacing: 12) {
            ProfileIcon(icon: "figure.martial.arts", tint: .sbCyan)
            Text("profile.sport.label")
                .font(SBFont.body())
                .foregroundColor(.sbTextPrimary)
            Spacer()
            Menu {
                Button {
                    profile.practicedSportIDs = []
                    profile.sportDaysPerWeek = 0
                    profile.sportWeekdays = []
                } label: {
                    Label { Text("onboarding.sport.none") } icon: { Image(systemName: "dumbbell.fill") }
                }
                ForEach(SportLibrary.all) { sport in
                    Button {
                        if profile.practicedSportIDs.contains(sport.id) {
                            profile.practicedSportIDs.removeAll { $0 == sport.id }
                            if profile.practicedSportIDs.isEmpty { profile.sportDaysPerWeek = 0; profile.sportWeekdays = [] }
                        } else {
                            profile.practicedSportIDs.append(sport.id)
                            if profile.sportDaysPerWeek == 0 { profile.sportDaysPerWeek = 3 }
                        }
                    } label: {
                        Label {
                            Text(verbatim: PT(sport.nameKey))
                        } icon: {
                            Image(systemName: profile.practicedSportIDs.contains(sport.id)
                                  ? "checkmark.circle.fill" : sport.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: sportSummary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(SBFont.heading(14))
                .foregroundColor(.sbAccent)
            }
        }
        .padding(.vertical, 12)
    }

    private var sportSummary: String {
        let ids = profile.practicedSportIDs
        if ids.isEmpty { return NSLocalizedString("onboarding.sport.none", comment: "") }
        if ids.count == 1, let s = SportLibrary.byID(ids[0]) { return PT(s.nameKey) }
        return String(format: NSLocalizedString("profile.sport.count", comment: ""), ids.count)
    }

    /// Every sport the user practises, each one removable.
    ///
    /// The row above can only ever say "2 sports" — with several picked you
    /// could not see *which* ones without opening the menu, and removing one
    /// meant hunting for it in a long list.
    private var selectedSportsRow: some View {
        // Laid out in rows of two rather than a horizontal ScrollView: a scroll
        // view nested inside the page's own scroll view swallowed the taps, and
        // anything past the third chip was invisible anyway.
        let sports = profile.practicedSportIDs.compactMap { SportLibrary.byID($0) }
        let rows = stride(from: 0, to: sports.count, by: 2).map {
            Array(sports[$0 ..< min($0 + 2, sports.count)])
        }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { sport in sportChip(sport) }
                    Spacer(minLength: 0)   // keeps every row left-aligned
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func sportChip(_ sport: SportActivity) -> some View {
        Button {
            profile.practicedSportIDs.removeAll { $0 == sport.id }
            if profile.practicedSportIDs.isEmpty { profile.sportDaysPerWeek = 0; profile.sportWeekdays = [] }
            HapticManager.light()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sport.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(verbatim: PT(sport.nameKey))
                    .font(SBFont.label(12))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.sbAccent.opacity(0.6))
            }
            .foregroundColor(.sbAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.sbAccentDim))
            // Rectangle, not Capsule: a Capsule content shape here left the
            // chip unhittable. This is the same shape the list rows use.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Which weekdays the sport happens — tap to toggle. Knowing the days,
    /// not just how many, lets the plan keep heavy gym work away from the day
    /// before a class and give practice days more carbohydrates.
    private var daysRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProfileIcon(icon: "calendar", tint: .sbCyan)
                Text("profile.sport.weekdays")
                    .font(SBFont.body())
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                Text(verbatim: profile.sportWeekdays.isEmpty
                     ? NSLocalizedString("profile.sport.pickDays", comment: "")
                     : String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: ""), profile.sportWeekdays.count))
                    .font(SBFont.caption())
                    .foregroundColor(profile.sportWeekdays.isEmpty ? .orange : .sbTextSecondary)
            }

            SportWeekdayPicker(weekdays: $profile.sportWeekdays)

            if let suggested = suggestedWeekdays, suggested != profile.sportWeekdays {
                Button {
                    HapticManager.light()
                    profile.sportWeekdays = suggested
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text(verbatim: String(format: NSLocalizedString("profile.sport.suggest", comment: ""),
                                              suggested.map(weekdayInitial).joined(separator: " · ")))
                            .font(SBFont.caption())
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Text("profile.sport.useDays")
                            .font(SBFont.label(12))
                    }
                    .foregroundColor(.sbAccent)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.sbAccentDim))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }

    private func weekdayInitial(_ wd: Int) -> String {
        var cal = Calendar.current
        cal.locale = language.locale
        return cal.veryShortWeekdaySymbols[wd - 1]
    }

    /// Weekdays with at least two logged sessions of the user's sports in the
    /// last four weeks — their real schedule, offered with one tap.
    private var suggestedWeekdays: [Int]? {
        let cutoff = Date().addingTimeInterval(-28 * 86_400)
        let days = SportSessionStore.shared.history
            .filter { profile.practicedSportIDs.contains($0.sportId) && $0.startedAt >= cutoff }
            .map { Calendar.current.component(.weekday, from: $0.startedAt) }
        let counts = Dictionary(days.map { ($0, 1) }, uniquingKeysWith: +)
        let picked = counts.filter { $0.value >= 2 }.map(\.key).sorted()
        return picked.isEmpty ? nil : picked
    }

    // MARK: - Health & data

    private var healthSection: some View {
        ProfileSection(title: "Health & Data") {
            ProfileRow(icon: "heart.fill", tint: .sbRed, label: "Apple Health",
                       value: health.isAuthorized
                            ? NSLocalizedString("Connected", comment: "")
                            : NSLocalizedString("Not connected", comment: ""),
                       chevron: true) {
                if health.isAuthorized { showMyData = true } else { health.requestAuthorization() }
            }
            ProfileDivider()
            ProfileRow(icon: "clock.arrow.circlepath", tint: .sbAccent,
                       label: "Workout History", value: "\(workouts.history.count)", chevron: true) {
                NotificationCenter.default.post(name: .switchToTab, object: 2)
            }
            ProfileDivider()
            ProfileRow(icon: "scalemass.fill", tint: .sbAccent,
                       label: "RM Calculator", chevron: true) {
                showRMCalculator = true
            }
        }
    }

    // MARK: - Other

    private var otherSection: some View {
        ProfileSection(title: "Other") {
            ProfileRow(icon: "gearshape.fill", tint: .sbTextSecondary,
                       label: "Settings", value: language.currentLanguage.flag, chevron: true) {
                showSettings = true
            }
            ProfileDivider()
            ProfileRow(icon: "info.circle.fill", tint: .sbTextSecondary,
                       label: "About", chevron: true) { showAbout = true }
            ProfileDivider()
            ProfileRow(icon: "lock.shield.fill", tint: .sbTextSecondary,
                       label: "Privacy Policy", chevron: true) { showPrivacy = true }
            ProfileDivider()
            ProfileRow(icon: "book.closed.fill", tint: .sbTextSecondary,
                       label: "sources.title", chevron: true) { showSources = true }
            ProfileDivider()
            ProfileRow(icon: "envelope.fill", tint: .sbTextSecondary,
                       label: "Contact Support", chevron: true) {
                if let url = URL(string: "mailto:\(Config.supportEmail)?subject=PowerPump%20Support") {
                    UIApplication.shared.open(url)
                }
            }
            ProfileDivider()
            ProfileRow(icon: "star.fill", tint: .orange,
                       label: "Rate PowerPump", chevron: true) {
                if let url = URL(string: "itms-apps://itunes.apple.com/app/id\(Config.appStoreID)?action=write-review") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Achievements sheet

/// Your badges, unlocked ones first.
///
/// These used to sit in the middle of the Progress tab, where they competed
/// with the charts. Progress answers "how am I doing"; badges are a reward you
/// go looking for, so they belong behind the profile's own card.
struct AchievementsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var workouts = WorkoutStore.shared
    @ObservedObject private var foodLog  = FoodLogStore.shared
    @ObservedObject private var progress = ProgressStore.shared

    var body: some View {
        let unlocked = workouts.unlockedAchievements(
            foodLogHasEntries: !foodLog.todayEntries.isEmpty,
            weightLogged: !progress.weightEntries.isEmpty
        )
        let locked = Achievement.allCases.filter { !unlocked.contains($0) }

        return NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Achievements")
                                .font(SBFont.display(24))
                                .foregroundColor(.sbTextPrimary)
                            Spacer()
                            Text(verbatim: "\(unlocked.count)/\(Achievement.allCases.count)")
                                .font(SBFont.heading(16))
                                .foregroundColor(.sbAccent)
                        }

                        if unlocked.isEmpty {
                            Text("Complete workouts and log food to earn badges.")
                                .font(SBFont.caption())
                                .foregroundColor(.sbTextSecondary)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: 12) {
                            ForEach(unlocked + locked) { achievement in
                                AchievementBadge(achievement: achievement,
                                                 unlocked: unlocked.contains(achievement))
                            }
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.sbAccent)
                }
            }
        }
    }
}

// MARK: - My data sheet

/// Everything the profile screen used to show inline but rarely needs: today's
/// Apple Health numbers and the weekly heart rate chart.
struct MyDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile = UserProfile.shared
    @ObservedObject private var health  = HealthKitService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        SBCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "heart.fill").foregroundColor(.sbRed)
                                    Text("Apple Health")
                                        .font(SBFont.heading())
                                        .foregroundColor(.sbTextPrimary)
                                    Spacer()
                                    if health.isAuthorized {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.sbGreen)
                                    }
                                }

                                if !health.isAvailable {
                                    Text("Apple Health is not available on this device.")
                                        .font(SBFont.caption())
                                        .foregroundColor(.sbTextSecondary)
                                } else if health.isAuthorized {
                                    HStack(spacing: 0) {
                                        healthStat("\(health.stepsToday)", "Steps", "figure.walk")
                                            .frame(maxWidth: .infinity)
                                        Divider().frame(height: 36)
                                        healthStat("\(Int(health.activeEnergyToday))", "Active kcal", "flame.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    Text("Workouts, meals, and water sync automatically.")
                                        .font(SBFont.label(11))
                                        .foregroundColor(Color.sbTextSecondary.opacity(0.6))
                                } else {
                                    Text("Connect Apple Health to sync workouts, nutrition, and activity data.")
                                        .font(SBFont.caption())
                                        .foregroundColor(.sbTextSecondary)
                                        .lineSpacing(3)
                                    SBPrimaryButton(title: "Connect Apple Health") {
                                        health.requestAuthorization()
                                    }
                                }
                            }
                        }

                        if health.isAuthorized {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.sbRed)
                                        .font(.system(size: 16))
                                    Text("Weekly Heart Rate")
                                        .font(SBFont.heading())
                                        .foregroundColor(.sbTextPrimary)
                                }
                                HeartRateChartCard(samples: health.weeklyHeartRate)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("My Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.sbAccent)
                }
            }
            .onAppear { if health.isAuthorized { health.fetchTodayStats() } }
        }
    }

    private func healthStat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.sbRed)
            Text(value)
                .font(SBFont.heading(18))
                .foregroundColor(.sbTextPrimary)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(SBFont.label(10))
                .foregroundColor(.sbTextSecondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Building blocks

/// One of the three shortcuts under the avatar.
private struct ProfileQuickCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
                Spacer(minLength: 6)
                Text(LocalizedStringKey(title))
                    .font(SBFont.label(11))
                    .foregroundColor(.sbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(verbatim: value)
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 92)
            .padding(13)
            .background(Color.sbSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
        }
        .buttonStyle(.plain)
    }
}

/// A titled group of rows — replaces the old wall of separate cards.
private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(LocalizedStringKey(title))
                .font(SBFont.label(12))
                .foregroundColor(.sbTextSecondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .background(Color.sbSurface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
        }
    }
}

private struct ProfileIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.15))
            .cornerRadius(8)
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Divider().background(Color.sbBorder)
    }
}

private struct ProfileRow: View {
    let icon: String
    let tint: Color
    let label: String
    var value: String? = nil
    var chevron: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            ProfileIcon(icon: icon, tint: tint)
            Text(LocalizedStringKey(label))
                .font(SBFont.body())
                .foregroundColor(.sbTextPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(verbatim: value)
                    .font(SBFont.heading(14))
                    .foregroundColor(.sbTextSecondary)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.sbTextSecondary.opacity(0.45))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
