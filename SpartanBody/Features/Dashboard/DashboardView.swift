import SwiftUI

struct DashboardView: View {
    @ObservedObject private var profile    = UserProfile.shared
    @ObservedObject private var foodLog    = FoodLogStore.shared
    @ObservedObject private var workouts   = WorkoutStore.shared
    @ObservedObject private var challenges = ChallengeStore.shared
    @ObservedObject private var health     = HealthKitService.shared
    @ObservedObject private var planStore  = PlanStore.shared
    @ObservedObject private var history    = CoachHistoryStore.shared
    @State private var showHistory      = false
    @State private var showCoach        = false
    @State private var showNutrition    = false
    @State private var showChallenges   = false
    @State private var showBarcodeScanner = false
    @State private var showLogWeight    = false
    @State private var showChat         = false
    @State private var showFormVideo    = false
    @State private var showSettings     = false
    @State private var appeared         = false

    // Coach insights — recomputed when the view appears.
    @State private var coachAlert: CoachInsightsService.CoachAlert?
    @State private var weeklyRecap: CoachInsightsService.WeeklyRecap =
        CoachInsightsService.WeeklyRecap(
            weekRange: "", workoutsDone: 0, workoutsPlanned: 4,
            avgDailyCalories: 0, calorieTarget: 2000, avgWater: 0,
            weightChange: nil, highlight: "")
    private var isMonday: Bool { Calendar.current.component(.weekday, from: .now) == 2 }

    // Show the recap on Mondays, or any day if there's actual data to show.
    private var showWeeklyRecap: Bool {
        let isMonday = Calendar.current.component(.weekday, from: .now) == 2
        let hasData  = weeklyRecap.workoutsDone > 0 || weeklyRecap.avgDailyCalories > 0
        return isMonday && hasData
    }

    private var caloriesConsumed: Int { Int(foodLog.todayCalories) }
    /// Today's targets — higher on a heavy training day, lower on rest days.
    private var target: MacroTarget { planStore.todayTargets(for: profile) }
    private var caloriesBurned: Int {
        health.isAuthorized && health.activeEnergyToday > 0
            ? Int(health.activeEnergyToday)
            : workouts.todayCaloriesBurned
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return NSLocalizedString("Good morning,", comment: "")
        case 12..<17: return NSLocalizedString("Good afternoon,", comment: "")
        default:      return NSLocalizedString("Good evening,", comment: "")
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.sbBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                            .slideIn(appeared, delay: 0.0)
                        if let alert = coachAlert {
                            CoachAlertBanner(alert: alert)
                                .slideIn(appeared, delay: 0.04)
                        }
                        // Monday: last week's review from the coach history —
                        // the same one the Profile shows, not a second system.
                        // The old recap stays only until a first review exists.
                        if isMonday, history.reviews.first != nil {
                            CoachHistoryCard { showHistory = true }
                                .slideIn(appeared, delay: 0.06)
                                .sheet(isPresented: $showHistory) { CoachHistoryView() }
                        } else if showWeeklyRecap {
                            WeeklyRecapCard(recap: weeklyRecap)
                                .slideIn(appeared, delay: 0.06)
                        }
                        calorieRingSection
                            .slideIn(appeared, delay: 0.08)
                        HomeStatsGrid { showLogWeight = true }
                            .slideIn(appeared, delay: 0.14)
                        // "How am I doing" → "what do I train today" → "log it".
                        // The coach used to sit at the very bottom, where the
                        // user had to scroll past everything to find it.
                        CoachTodayCard { showCoach = true }
                            .slideIn(appeared, delay: 0.20)
                            .fullScreenCover(isPresented: $showCoach) { AICoachView() }
                        quickActionsSection
                            .slideIn(appeared, delay: 0.26)
                        // waterSection is gone — the water tile in
                        // HomeStatsGrid carries the same eight glasses.
                        challengeCard
                            .slideIn(appeared, delay: 0.38)
                        // The tab bar floats over the scroll view — 32pt left
                        // the last card sitting behind it.
                        Spacer(minLength: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
            if health.isAuthorized { health.fetchTodayStats() }
            // A week after the plan was built, read the new history and plan
            // the next one — otherwise week one repeats forever.
            planStore.regenerateIfStale()
            if isMonday { history.refresh() }
            // The active challenge card is on this screen, so check the
            // automatic goals here too, not only in the challenges list.
            challenges.autoCheck()
            coachAlert  = CoachInsightsService.currentAlert()
            weeklyRecap = CoachInsightsService.weeklyRecap()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(SBFont.body())
                    .foregroundColor(.sbTextSecondary)
                Text(profile.name.isEmpty ? "Spartan" : profile.name)
                    .font(SBFont.display(28))
                    .foregroundColor(.sbTextPrimary)
            }
            Spacer()

            if health.isAuthorized && health.stepsToday > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.sbAccent)
                    Text("\(health.stepsToday)")
                        .font(SBFont.caption())
                        .fontWeight(.bold)
                        .foregroundColor(.sbTextPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.sbAccentDim)
                .cornerRadius(10)
            }

            if workouts.currentStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)
                    Text("\(workouts.currentStreak)")
                        .font(SBFont.caption())
                        .fontWeight(.bold)
                        .foregroundColor(.sbTextPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(10)
            }

            Button {
                HapticManager.light()
                showSettings = true
            } label: {
                ZStack {
                    Circle().fill(Color.sbSurface).frame(width: 46, height: 46)
                    Image(systemName: "bell.fill")
                        .foregroundColor(.sbAccent)
                        .font(.system(size: 18))
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Calorie Ring
    private var calorieRingSection: some View {
        SBCard {
            VStack(spacing: 16) {
                HStack {
                    Text("Today's Calories")
                        .font(SBFont.heading())
                        .foregroundColor(.sbTextPrimary)
                    Spacer()
                    SBTag(text: profile.goal.rawValue)
                }

                // Ring beside the macros instead of stacked in two separate
                // cards: same information, roughly half the height, so the
                // coach card and the tiles below are reachable without
                // scrolling.
                HStack(alignment: .center, spacing: 18) {
                    calorieRing
                    VStack(spacing: 11) {
                        MacroRow(name: "Protein", current: Int(foodLog.todayProtein),
                                 target: target.protein,
                                 unit: "g", color: .sbAccent)
                        MacroRow(name: "Carbs", current: Int(foodLog.todayCarbs),
                                 target: target.carbs,
                                 unit: "g", color: .sbGreen)
                        MacroRow(name: "Fat", current: Int(foodLog.todayFat),
                                 target: target.fat,
                                 unit: "g", color: Color.orange)
                    }
                }

                Divider().background(Color.sbBorder)

                // Kept from the old three stat boxes — burned calories appear
                // nowhere else, so dropping this row would lose them.
                HStack(spacing: 0) {
                    miniStat("\(max(target.kcal - caloriesConsumed, 0))",
                             "Remaining", .sbTextPrimary)
                    miniStat("\(caloriesConsumed)", "Consumed", .sbGreen)
                    miniStat("\(caloriesBurned)", "Burned", .sbRed)
                }

                // Food logging used to be a quick action; it now sits on the
                // card that shows what was eaten.
                Button {
                    HapticManager.light()
                    showNutrition = true
                } label: {
                    Label("quick.logMeal", systemImage: "plus.circle.fill")
                        .font(SBFont.body(15))
                        .fontWeight(.semibold)
                        .foregroundColor(.sbAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.sbAccentDim)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showNutrition = true }
    }

    private var calorieRing: some View {
        ZStack {
            Circle()
                .stroke(Color.sbSurfaceRaised, lineWidth: 11)
            Circle()
                .trim(from: 0, to: min(Double(caloriesConsumed) / Double(max(target.kcal, 1)), 1.0))
                .stroke(
                    caloriesConsumed > target.kcal
                        ? AnyShapeStyle(Color.sbRed)
                        : AnyShapeStyle(AngularGradient(
                            colors: [.sbAccent, .sbCyan, .sbAccent],
                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.sbAccent.opacity(caloriesConsumed > 0 ? 0.35 : 0), radius: 6)
                .animation(.spring(), value: caloriesConsumed)

            VStack(spacing: 0) {
                Text("\(caloriesConsumed)")
                    .font(SBFont.display(25))
                    .foregroundColor(.sbTextPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(verbatim: String(format: NSLocalizedString("of %lld", comment: ""),
                                      target.kcal))
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 112, height: 112)
    }

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(SBFont.heading(16))
                .foregroundColor(color)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(SBFont.label(10))
                .foregroundColor(.sbTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Challenge card

    private var challengeCard: some View {
        Button { showChallenges = true } label: {
            if let active = challenges.active.first, let def = active.definition {
                // Show active challenge progress
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(def.color.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: def.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(def.color)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(def.name))
                                .font(SBFont.heading(15))
                                .foregroundColor(.sbTextPrimary)
                            if challenges.active.count > 1 {
                                Text("+\(challenges.active.count - 1)")
                                    .font(SBFont.label(10))
                                    .foregroundColor(.sbTextSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.sbSurfaceRaised)
                                    .cornerRadius(6)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.sbBorder).frame(height: 5)
                                RoundedRectangle(cornerRadius: 3).fill(def.color)
                                    .frame(width: geo.size.width * active.progress, height: 5)
                            }
                        }
                        .frame(height: 5)
                        Text("\(active.completedDayKeys.count)/\(active.totalDays) days · \(NSLocalizedString(active.isDayComplete(.now) ? "Done today ✓" : "Pending today", comment: ""))")
                            .font(SBFont.label(11))
                            .foregroundColor(active.isDayComplete(.now) ? def.color : .sbTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.sbAccent)
                }
                .padding(14)
                .background(Color.sbSurface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(def.color.opacity(0.35), lineWidth: 1.5))
            } else {
                // No active challenge — invite to start
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start a Challenge")
                            .font(SBFont.heading(15))
                            .foregroundColor(.sbTextPrimary)
                        Text("Build consistency with 7–30 day goals")
                            .font(SBFont.caption())
                            .foregroundColor(.sbTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.sbAccent)
                }
                .padding(14)
                .background(Color.sbSurface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.35), lineWidth: 1.5))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)

            // Meal, weight and run were dropped: food is logged from Recipes,
            // the weight tile above logs a weigh-in, and the tab bar opens
            // running in one tap. The coach chat and the form check are the
            // two things only reachable from deep inside other screens.
            HStack(spacing: 10) {
                QuickActionButton(icon: "bubble.left.and.text.bubble.right.fill", label: "quick.coach") {
                    HapticManager.medium()
                    showChat = true
                }
                QuickActionButton(icon: "video.badge.waveform", label: "quick.form") {
                    HapticManager.light()
                    showFormVideo = true
                }
                QuickActionButton(icon: "barcode.viewfinder", label: "Barcode") {
                    HapticManager.light()
                    showBarcodeScanner = true
                }
            }
        }
        .fullScreenCover(isPresented: $showChat)      { CoachChatView() }
        .fullScreenCover(isPresented: $showFormVideo) { VideoFormAnalysisView() }
        .sheet(isPresented: $showLogWeight)       { LogWeightSheet() }
        .sheet(isPresented: $showNutrition)       { NutritionView() }
        .sheet(isPresented: $showChallenges)      { ChallengesView() }
        .sheet(isPresented: $showBarcodeScanner)  {
            BarcodeScanSheet { item in
                FoodLogStore.shared.add(item, grams: 100, meal: .snack)
                HapticManager.success()
            }
        }
    }
}

private struct MacroRow: View {
    let name: String
    let current: Int
    let target: Int
    let unit: String
    let color: Color

    private var progress: Double {
        target > 0 ? Double(current) / Double(target) : 0
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(LocalizedStringKey(name))
                    .font(SBFont.body())
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                Text("\(current) / \(target) \(unit)")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .monospacedDigit()
            }
            SBProgressBar(progress: progress, color: color)
        }
    }
}

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sbAccent.opacity(0.15))
                        .frame(height: 52)
                    Image(systemName: icon)
                        .foregroundColor(.sbAccent)
                        .font(.system(size: 20, weight: .semibold))
                }
                Text(LocalizedStringKey(label))
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
