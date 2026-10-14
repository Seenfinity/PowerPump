import SwiftUI

enum WorkoutTab: String, CaseIterable {
    case gym, run, sports

    var titleKey: String {
        switch self {
        case .gym:    return "workout.tab.gym"
        case .run:    return "workout.tab.run"
        case .sports: return "workout.tab.sports"
        }
    }

    var icon: String {
        switch self {
        case .gym:    return "dumbbell.fill"
        case .run:    return "figure.run"
        case .sports: return "trophy.fill"
        }
    }
}

/// Lets another screen open Workouts on a specific section.
///
/// A notification would race: the dashboard posts before `WorkoutsView` has
/// been built, so nothing is listening yet. Parking the request here and
/// reading it on appear works whichever order the two happen in.
enum WorkoutRouter {
    @MainActor static var pendingTab: WorkoutTab?
}

struct WorkoutsView: View {
    @ObservedObject private var store = WorkoutStore.shared
    @ObservedObject private var runStore = RunStore.shared
    @State private var showActive = false
    @State private var showSaveRoutine = false
    @State private var showRunning = false
    @State private var showRunningPrograms = false
    @State private var showSports = false
    @State private var showFormVideo = false
    @ObservedObject private var chat = CoachChatStore.shared
    @State private var routineName = ""
    @State private var tab: WorkoutTab = .gym
    @State private var showCoach = false
    @ObservedObject private var plans = PlanStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header

                        // Resume banner always visible so an active session is
                        // never hidden behind a tab.
                        if store.activeSession != nil {
                            resumeBanner
                        }

                        tabSelector

                        switch tab {
                        case .gym:    gymTab
                        case .run:    runTab
                        case .sports: sportsTab
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showActive) {
            ActiveWorkoutView(isPresented: $showActive)
        }
        .fullScreenCover(isPresented: $showRunning) {
            RunningView()
        }
        .sheet(isPresented: $showRunningPrograms) {
            RunningProgramsView()
        }
        .sheet(isPresented: $showSports) {
            SportsCatalogView()
        }
        .fullScreenCover(isPresented: $showFormVideo) {
            VideoFormAnalysisView()
        }
        .fullScreenCover(isPresented: $showCoach) { AICoachView() }
        // Spartan's recap pops up once the workout screen has closed.
        .sheet(item: Binding(
            get: { showActive ? nil : chat.pendingRecap.map(RecapID.init) },
            set: { if $0 == nil { chat.pendingRecap = nil } })) { r in
            SpartanRecapSheet(messageID: r.id)
        }
        .onAppear {
            if let pending = WorkoutRouter.pendingTab {
                tab = pending
                WorkoutRouter.pendingTab = nil
            }
        }
    }

    // MARK: - Tab selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(WorkoutTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { tab = t }
                    HapticManager.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(LocalizedStringKey(t.titleKey))
                            .font(SBFont.label(13))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(tab == t ? .white : .sbTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tab == t ? Color.sbAccent : Color.clear)
                    .cornerRadius(11)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sbSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
        .padding(.horizontal, 20)
    }

    // MARK: - Tab content

    /// Plan first: the week, what's on today and the next workout, then
    /// shortcuts, the programs and what was done lately.
    private var gymTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            if plans.plan != nil { weekSection }
            quickActions
            programsShelf
            if !store.templates.isEmpty { routinesSection }
            if !store.history.isEmpty { recentSection }
        }
    }

    private func start(_ template: WorkoutTemplate) {
        store.start(template: template)
        HapticManager.medium()
        showActive = true
    }

    // MARK: - Your week

    private var trainedToday: Bool {
        store.history.contains { Calendar.current.isDateInToday($0.startedAt) && $0.completedSets > 0 }
    }

    /// The next gym day of the plan: today if it hasn't been done yet.
    private var nextWorkout: (day: DayPlan, offset: Int)? {
        let cal = Calendar.current
        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: Date()),
                  let day = plans.dayPlan(on: date), day.isWorkout else { continue }
            if offset == 0 && trainedToday { continue }
            return (day, offset)
        }
        return nil
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("workout.week.title", action: "workout.week.seePlan") { showCoach = true }
            WeekStrip(plans: plans, history: store.history)
                .padding(.horizontal, 20)
            if let today = plans.todayPlan, !(today.isWorkout && !trainedToday) {
                TodayCard(day: today, done: today.isWorkout && trainedToday)
                    .padding(.horizontal, 20)
            }
            if let next = nextWorkout {
                sectionTitle("workout.next.title")
                    .padding(.top, 4)
                NextWorkoutCard(day: next.day, offset: next.offset) {
                    start(PlanWorkout.template(for: next.day))
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey, action: LocalizedStringKey? = nil,
                              perform: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(SBFont.heading(18))
                .foregroundColor(.sbTextPrimary)
            Spacer()
            if let action, let perform {
                Button(action: perform) {
                    Text(action).font(SBFont.caption()).foregroundColor(.sbAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Shortcuts

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickTile(icon: "bolt.fill", title: "workout.quick.free") {
                store.startEmpty()
                showActive = true
            }
            QuickTile(icon: "video.badge.waveform", title: "quick.form") {
                HapticManager.medium()
                showFormVideo = true
            }
            NavigationLink(destination: ExercisesView()) {
                QuickTileLabel(icon: "list.bullet.rectangle", title: "workout.quick.library")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Programs

    private var programsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Programs")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ProgramLibrary.all) { program in
                        Button { start(program.template) } label: {
                            ProgramPhotoCard(program: program)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("workout.recent.title", action: "workout.seeAll") {
                NotificationCenter.default.post(name: .switchToTab, object: 2)
            }
            VStack(spacing: 0) {
                ForEach(Array(store.history.prefix(3).enumerated()), id: \.element.id) { i, session in
                    RecentRow(session: session)
                    if i < min(3, store.history.count) - 1 { Divider().background(Color.sbBorder) }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.sbSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
            .padding(.horizontal, 20)
        }
    }

    private var runTab: some View {
        VStack(spacing: 20) {
            runCard
            runningProgramsCard
            recentRunsSection
        }
    }

    private var sportsTab: some View {
        // The full 28-sport catalog embedded directly in the tab.
        // Details pushed from here open under the floating tab bar, which
        // otherwise hides their "Start session" button.
        SportsCatalogContent(detailBottomInset: SBTabBar.overlapInset)
            .padding(.horizontal, 20)
    }

    // MARK: - Recent runs (Run tab)

    @ViewBuilder
    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("Recent runs"))
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)
                .padding(.horizontal, 20)

            if runStore.history.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 26))
                        .foregroundColor(.sbTextSecondary.opacity(0.6))
                    Text(LocalizedStringKey("No runs yet. Start your first one!"))
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                    Spacer()
                }
                .padding(16)
                .background(Color.sbSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
                .padding(.horizontal, 20)
            } else {
                ForEach(runStore.history.prefix(5)) { session in
                    RunHistoryRow(session: session)
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Workouts")
                .font(SBFont.display(28))
                .foregroundColor(.sbTextPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var resumeBanner: some View {
        Button { showActive = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.sbAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in progress")
                        .font(SBFont.heading(14))
                        .foregroundColor(.sbTextPrimary)
                    Text("Tap to resume")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.sbAccent)
            }
            .padding(16)
            .background(Color.sbAccent.opacity(0.1))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var sportsCard: some View {
        Button {
            HapticManager.medium()
            showSports = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.sbGreen.opacity(0.32), Color.sbGreen.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.sbGreen)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sports")
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                    Text("Cycling · Yoga · Swim · Diving · 30+ more")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.sbTextSecondary.opacity(0.6))
            }
            .padding(16)
            .background(Color.sbSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbGreen.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Walking & Running Programs

    private var runningProgramsCard: some View {
        Button {
            HapticManager.medium()
            showRunningPrograms = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.sbAccent.opacity(0.35), Color.sbAccent.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.sbAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Walk & Run Programs")
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                    Text("Lose weight · 5K · Pace · Voice coach")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.sbTextSecondary.opacity(0.6))
            }
            .padding(16)
            .background(Color.sbSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Run / Walk

    private var runCard: some View {
        Button {
            HapticManager.medium()
            showRunning = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.sbAccent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: "figure.run")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.sbAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Run / Walk")
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                    Text("GPS · Live route · Pace & calories")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.sbTextSecondary.opacity(0.6))
            }
            .padding(16)
            .background(Color.sbSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Routines")
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)
                .padding(.horizontal, 20)

            ForEach(store.templates) { template in
                TemplateCard(template: template) {
                    store.start(template: template)
                    showActive = true
                }
                .padding(.horizontal, 20)
            }
        }
    }

}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let onStart: () -> Void
    @ObservedObject private var store = WorkoutStore.shared

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(WorkoutName.display(template.name))
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                Text("\(template.exercises.count) exercise\(template.exercises.count == 1 ? "" : "s")")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
            }

            Spacer()

            Button(action: onStart) {
                Text("Start")
                    .font(SBFont.caption())
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.sbAccent)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteTemplate(template)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exercise Picker Sheet

struct ExercisePickerView: View {
    let onSelect: (String) -> Void
    @State private var searchText = ""
    @State private var selectedCategory: MuscleGroup? = nil
    @Environment(\.dismiss) private var dismiss

    private var filtered: [Exercise] {
        var list = ExerciseDatabase.all
        if let cat = selectedCategory { list = list.filter { $0.category == cat } }
        if !searchText.isEmpty {
            let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            list = list.filter {
                $0.name.range(of: searchText, options: opts) != nil
                || EXL($0.name).range(of: searchText, options: opts) != nil
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundColor(.sbTextSecondary)
                        TextField("Search exercises...", text: $searchText)
                            .font(SBFont.body())
                            .foregroundColor(.sbTextPrimary)
                    }
                    .padding(12)
                    .background(Color.sbSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sbBorder))
                    .padding(16)

                    // Category filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(MuscleGroup.allCases, id: \.self) { g in
                                FilterChip(label: g.rawValue, isSelected: selectedCategory == g) {
                                    selectedCategory = selectedCategory == g ? nil : g
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 12)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { exercise in
                                Button { onSelect(exercise.id) } label: {
                                    HStack(spacing: 12) {
                                        if let name = ExerciseDatabase.muscleIconNames[exercise.id],
                                           let img = UIImage(named: name) {
                                            Image(uiImage: img)
                                                .resizable().scaledToFill()
                                                .frame(width: 42, height: 42)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.sbSurfaceRaised)
                                                .frame(width: 42, height: 42)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(EXL(exercise.name))
                                                .font(SBFont.body())
                                                .foregroundColor(.sbTextPrimary)
                                            Text(EXL(exercise.primaryMuscle))
                                                .font(SBFont.caption())
                                                .foregroundColor(.sbTextSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.sbAccent)
                                    }
                                    .padding(12)
                                    .background(Color.sbSurface)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sbBorder))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sbAccent)
                }
            }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SBFont.caption())
                .foregroundColor(isSelected ? .white : .sbTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.sbAccent : Color.sbSurface)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? Color.sbAccent : Color.sbBorder))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Run History Row (Run tab)

private struct RunHistoryRow: View {
    let session: RunSession

    private var durationText: String {
        let s = Int(session.movingSeconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: LanguageManager.shared.selectedCode)
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: session.startedAt)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sbAccent.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: session.activity.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.sbAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(session.activity.rawValue))
                        .font(SBFont.heading(15))
                        .foregroundColor(.sbTextPrimary)
                    Text(verbatim: "· \(dateText)")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                }
                Text(verbatim: String(format: "%.2f km · %@ · %d kcal",
                                      session.distanceKm, durationText, session.calories))
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.sbSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
    }
}


private struct RecapID: Identifiable { let id: UUID }

// MARK: - Gym tab pieces

/// Monday to Sunday of this week, from the plan: gym, sport or rest, with
/// today marked and done days ticked.
private struct WeekStrip: View {
    @ObservedObject var plans: PlanStore
    let history: [WorkoutSession]

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func letter(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: LanguageManager.shared.selectedCode)
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f.string(from: date).uppercased()
    }

    var body: some View {
        let cal = Calendar.current
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { date in
                let day = plans.dayPlan(on: date)
                let today = cal.isDateInToday(date)
                let past = date < cal.startOfDay(for: Date())
                let done = history.contains { cal.isDate($0.startedAt, inSameDayAs: date) && $0.completedSets > 0 }
                VStack(spacing: 5) {
                    Text(verbatim: letter(date))
                        .font(SBFont.label(11))
                        .foregroundColor(today ? .sbAccent : .sbTextSecondary)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: icon(day))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tint(day))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(tint(day).opacity(day == nil ? 0 : 0.18)))
                            .overlay(Circle().stroke(day == nil ? Color.sbBorder : .clear))
                        if done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.sbGreen)
                                .background(Circle().fill(Color.sbBackground))
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 13).fill(today ? Color.sbAccentDim : .clear))
                .opacity(past && !done ? 0.45 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: day?.focus ?? ""))
            }
        }
    }

    private func icon(_ day: DayPlan?) -> String {
        guard let day else { return "circle.dotted" }
        if day.isWorkout { return "dumbbell.fill" }
        if let id = day.sport, let sport = SportLibrary.byID(id) { return sport.icon }
        return "leaf.fill"
    }

    private func tint(_ day: DayPlan?) -> Color {
        guard let day else { return .sbTextSecondary }
        if day.isWorkout { return .sbAccent }
        if day.isSportDay { return Color(hex: "#BF5AF2") }
        return .sbGreen
    }
}

/// What today holds when it isn't a gym session still to do.
private struct TodayCard: View {
    let day: DayPlan
    let done: Bool

    private var sport: SportActivity? { day.sport.flatMap(SportLibrary.byID) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark" : sport?.icon ?? "figure.walk")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(done ? .sbGreen : sport != nil ? Color(hex: "#BF5AF2") : .sbGreen)
                .frame(width: 42, height: 42)
                .background((done || sport == nil ? Color.sbGreen : Color(hex: "#BF5AF2")).opacity(0.15))
                .cornerRadius(12)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: done ? NSLocalizedString("workout.today.done", comment: "")
                     : String(format: NSLocalizedString("workout.today", comment: ""), locale: .current, title))
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                Text(verbatim: subtitle)
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    private var title: String {
        sport.map { NSLocalizedString($0.nameKey, comment: "") } ?? day.focus
    }

    private var subtitle: String {
        if done { return day.focus }
        if sport != nil { return NSLocalizedString("workout.today.sport.sub", comment: "") }
        return day.exercises.prefix(2).map(EXLPlanLine).joined(separator: " · ")
    }
}

/// The next gym day of the plan, big, with the way to start it.
private struct NextWorkoutCard: View {
    let day: DayPlan
    let offset: Int
    let onStart: () -> Void

    private var template: WorkoutTemplate { PlanWorkout.template(for: day) }

    private var when: String {
        switch offset {
        case 0: return NSLocalizedString("workout.next.today", comment: "")
        case 1: return NSLocalizedString("workout.next.tomorrow", comment: "")
        default:
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            let f = DateFormatter()
            f.locale = Locale(identifier: LanguageManager.shared.selectedCode)
            f.setLocalizedDateFormatFromTemplate("EEEE")
            return String(format: NSLocalizedString("workout.next.day", comment: ""), locale: .current,
                          f.string(from: date).capitalized)
        }
    }

    var body: some View {
        Button(action: onStart) {
            ZStack(alignment: .bottomLeading) {
                // The photo fills a box of fixed height; on its own a filling
                // image is wider than the screen and pushes the page sideways.
                Color.clear
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .overlay(Image(CoachPhoto.name(for: day)).resizable().scaledToFill())
                    .clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0.1),
                                       .init(color: .black.opacity(0.25), location: 0.6),
                                       .init(color: .black.opacity(0.05), location: 1)],
                               startPoint: .bottom, endPoint: .top)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: when.uppercased())
                        .font(SBFont.label(11))
                        .tracking(1.2)
                        .foregroundColor(.sbCyan)
                    Text(verbatim: day.focus)
                        .font(SBFont.display(24))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(verbatim: String(format: NSLocalizedString("workout.next.meta", comment: ""), locale: .current,
                                          template.exercises.count, PlanWorkout.minutes(for: template)))
                        .font(SBFont.caption())
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.bottom, 6)
                    Label("workout.start", systemImage: "play.fill")
                        .font(SBFont.heading(14))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white))
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

private struct QuickTileLabel: View {
    let icon: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.sbAccent)
                .frame(width: 38, height: 38)
                .background(Color.sbAccentDim)
                .cornerRadius(11)
            Text(title)
                .font(SBFont.label(12))
                .foregroundColor(.sbTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(height: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
        .contentShape(Rectangle())
    }
}

private struct QuickTile: View {
    let icon: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { QuickTileLabel(icon: icon, title: title) }
            .buttonStyle(.plain)
    }
}

/// A built-in program as a photo card, tapped to start it.
private struct ProgramPhotoCard: View {
    let program: BuiltinProgram

    private var photo: String {
        switch program.id {
        case "prog_push":     return "photo_push"
        case "prog_pull":     return "photo_pull"
        case "prog_legs":     return "photo_legs"
        case "prog_fullbody": return "photo_deadlift"
        case "prog_core":     return "photo_cardio"
        default:              return "photo_general"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(width: 156, height: 178)
                .overlay(Image(photo).resizable().scaledToFill())
                .clipped()
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: PT(program.nameKey))
                    .font(SBFont.heading(15))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(verbatim: String(format: NSLocalizedString("workout.program.meta", comment: ""), locale: .current,
                                      program.estimatedMinutes, program.template.exercises.count))
                    .font(SBFont.label(11))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(11)
        }
        .frame(width: 156, height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 17))
    }
}

/// One finished session in the recent list.
private struct RecentRow: View {
    let session: WorkoutSession

    private var duration: String {
        let m = Int(session.duration) / 60
        return m < 60 ? "\(m) min" : String(format: "%dh %02dm", m / 60, m % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.sbAccent)
                .frame(width: 36, height: 36)
                .background(Color.sbSurfaceRaised)
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutName.display(session.name))
                    .font(SBFont.heading(14))
                    .foregroundColor(.sbTextPrimary)
                Text(verbatim: session.startedAt.formatted(.dateTime.day().month(.abbreviated)) + " · "
                     + String.localizedStringWithFormat(NSLocalizedString("spartan.recap.sets", comment: ""), session.completedSets)
                     + " · \(Int(session.totalVolume)) kg")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
            }
            Spacer()
            Text(verbatim: duration)
                .font(SBFont.heading(13))
                .foregroundColor(.sbAccent)
        }
        .padding(.vertical, 10)
    }
}
