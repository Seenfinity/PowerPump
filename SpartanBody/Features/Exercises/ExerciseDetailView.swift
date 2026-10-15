import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @State private var tab: DetailTab = .technique
    @State private var showLogSheet = false
    @State private var showFormCheck = false
    @State private var showSpartan = false
    @State private var scrollY: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var workouts = WorkoutStore.shared
    @ObservedObject private var logs = ExerciseLogStore.shared

    private enum DetailTab { case technique, history }
    private let heroHeight: CGFloat = 300

    private var supportedExercise: SupportedExercise? {
        SupportedExercise.allCases.first { $0.rawValue == exercise.id }
    }

    /// Past the photo, a compact bar keeps the name and the way back in view.
    private var collapsed: Bool { scrollY < -(heroHeight - 110) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.sbBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 0) {
                        facts
                        muscles
                        tabPicker
                        if tab == .technique {
                            ExerciseTechnique(exercise: exercise) { showSpartan = true }
                        } else {
                            ExerciseHistory(exercise: exercise,
                                            entries: ExerciseHistoryEntry.all(for: exercise.id,
                                                                              sessions: workouts.history,
                                                                              logs: logs.logs(for: exercise.id)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                // How far the page has moved, read from its top edge.
                .background(GeometryReader { g in
                    Color.clear.preference(key: DetailScrollKey.self, value: g.frame(in: .named("detail")).minY)
                })
            }
            .coordinateSpace(name: "detail")
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(DetailScrollKey.self) { scrollY = $0 }
            .modifier(ScrollOffsetReader(offset: $scrollY))
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }

            // Over the photo, below the clock; the compact bar takes over when scrolled.
            GlassCircleButton(icon: "chevron.left") { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(collapsed ? 0 : 1)
                .allowsHitTesting(!collapsed)

            topBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .edgeSwipeBackOnly()
        .sheet(isPresented: $showLogSheet) {
            LogExerciseSheet(exercise: exercise, isPresented: $showLogSheet)
        }
        .fullScreenCover(isPresented: $showFormCheck) {
            if let supported = supportedExercise {
                ExerciseCorrectionView(exercise: supported)
            }
        }
        .fullScreenCover(isPresented: $showSpartan) { CoachChatView() }
    }

    // MARK: Header

    /// The photo across the whole width, fading into the page, with the name on it.
    private var hero: some View {
        GeometryReader { g in
            let y = g.frame(in: .named("detail")).minY
            ZStack(alignment: .bottomLeading) {
                ExerciseAnimationView(exercise: exercise, fill: true)
                    // Pulling down stretches the photo instead of showing a gap.
                    .frame(width: g.size.width, height: heroHeight + max(0, y))
                    .clipped()
                    .offset(y: -max(0, y))
                LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0),
                                       .init(color: .clear, location: 0.28),
                                       .init(color: .clear, location: 0.45),
                                       .init(color: .sbBackground, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: eyebrow)
                        .font(SBFont.label(11))
                        .tracking(1.5)
                        .foregroundColor(.sbAccent)
                    Text(EXL(exercise.name))
                        .font(SBFont.display(28))
                        .foregroundColor(.sbTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(height: heroHeight)
    }

    /// "PECHO · BARRA · GIMNASIO"; the place is left out when it's both.
    private var eyebrow: String {
        var parts = [EXL(exercise.category.rawValue), EXL(exercise.equipment.rawValue)]
        if exercise.location != .both { parts.append(EXL(exercise.location.rawValue)) }
        return parts.joined(separator: " · ").uppercased()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.sbTextPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.sbSurfaceRaised)
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text("Back"))
            Text(EXL(exercise.name))
                .font(SBFont.heading(16))
                .foregroundColor(.sbTextPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.sbBorder).frame(height: 1), alignment: .bottom)
        .opacity(collapsed ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: collapsed)
        .allowsHitTesting(collapsed)
    }

    // MARK: Summary

    private var facts: some View {
        HStack(spacing: 8) {
            FactCell(value: "\(exercise.defaultSets)", label: EXL("Sets"))
            FactCell(value: EXLReps(exercise.defaultReps), label: EXL("Reps"))
            FactCell(value: EXL(exercise.difficulty.rawValue), label: NSLocalizedString("exercise.level", comment: ""),
                     accent: true)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// The main muscle stands out; the others go next to it.
    private var muscles: some View {
        FlowRow(spacing: 6) {
            MuscleChip(name: EXL(exercise.primaryMuscle), main: true)
            ForEach(exercise.secondaryMuscles, id: \.self) { MuscleChip(name: EXL($0), main: false) }
        }
        .padding(.bottom, 16)
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            segment(NSLocalizedString("exercise.tab.technique", comment: ""), .technique)
            segment(EXL("History"), .history)
        }
        .padding(3)
        .background(Color.sbSurfaceRaised)
        .cornerRadius(12)
        .padding(.bottom, 16)
    }

    private func segment(_ title: String, _ value: DetailTab) -> some View {
        Button {
            HapticManager.selection()
            withAnimation(.spring(response: 0.25)) { tab = value }
        } label: {
            Text(title)
                .font(SBFont.heading(14))
                .foregroundColor(tab == value ? .sbTextPrimary : .sbTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(tab == value ? Color.sbSurface : Color.clear)
                .cornerRadius(9)
                .shadow(color: .black.opacity(tab == value ? 0.2 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// Always visible above the floating tab bar: log it, or film it for a form check.
    private var actionBar: some View {
        HStack(spacing: 10) {
            if supportedExercise != nil {
                Button { showFormCheck = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.sbAccent)
                        .frame(width: 52, height: 52)
                        .background(Color.sbAccentDim)
                        .cornerRadius(15)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.sbAccent.opacity(0.45), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(EXL("Check Form")))
            }
            Button {
                HapticManager.light()
                showLogSheet = true
            } label: {
                Label(EXL("Log Exercise"), systemImage: "plus")
                    .font(SBFont.body())
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient.sbAccentGradient)
                    .cornerRadius(15)
                    .shadow(color: Color.sbAccent.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10 + SBTabBar.overlapInset)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.sbBorder).frame(height: 1), alignment: .top)
    }
}

// MARK: - Pieces

private struct MuscleChip: View {
    let name: String
    let main: Bool

    var body: some View {
        HStack(spacing: 5) {
            if main { Circle().fill(Color.sbAccent).frame(width: 6, height: 6) }
            Text(name)
                .font(SBFont.label(12))
                .foregroundColor(main ? .sbAccent : .sbTextSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(main ? Color.sbAccentDim : Color.clear)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(main ? Color.sbAccent.opacity(0.45) : Color.sbBorder))
    }
}

// MARK: - Technique

private struct ExerciseTechnique: View {
    let exercise: Exercise
    let askSpartan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(icon: "figure.stand", title: EXL("Setup"))
            Text(EXL(exercise.setup))
                .font(SBFont.body(14))
                .foregroundColor(.sbTextSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.sbSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
                .padding(.bottom, 18)

            SectionTitle(icon: "list.number", title: NSLocalizedString("exercise.steps", comment: ""))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        // Numbered dots joined by a line: a timeline of the rep.
                        VStack(spacing: 0) {
                            Text("\(i + 1)")
                                .font(SBFont.label(12))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.sbAccent))
                            if i < exercise.steps.count - 1 {
                                Rectangle().fill(Color.sbBorder).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        Text(EXL(step))
                            .font(SBFont.body(14))
                            .foregroundColor(.sbTextPrimary)
                            .lineSpacing(3)
                            .padding(.top, 3)
                            .padding(.bottom, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 8)

            if !exercise.tips.isEmpty {
                SectionTitle(icon: "star.fill", title: NSLocalizedString("exercise.keys", comment: ""))
                VStack(spacing: 8) {
                    ForEach(exercise.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.sbGreen)
                                .padding(.top, 2)
                            Text(EXL(tip))
                                .font(SBFont.body(14))
                                .foregroundColor(.sbTextPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.sbSurface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sbBorder))
                    }
                }
                .padding(.bottom, 18)
            }

            SpartanAskCard(exercise: exercise, action: askSpartan)
        }
    }
}

/// Opens Spartan with the question already asked; he answers from the
/// exercise library on every iPhone.
private struct SpartanAskCard: View {
    let exercise: Exercise
    let action: () -> Void

    var body: some View {
        Button {
            CoachChatStore.shared.send(String(format: NSLocalizedString("exercise.spartan.question", comment: ""),
                                              locale: .current, EXL(exercise.name)))
            action()
        } label: {
            HStack(spacing: 12) {
                CoachAvatar(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("exercise.spartan.title")
                        .font(SBFont.heading(14))
                        .foregroundColor(.sbTextPrimary)
                    Text("exercise.spartan.body")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.sbAccent)
            }
            .padding(12)
            .background(LinearGradient(colors: [Color.sbAccent.opacity(0.18), Color.sbCyan.opacity(0.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History

/// One time the exercise was done: a gym session or a quick log.
struct ExerciseHistoryEntry: Identifiable {
    let id = UUID()
    let date: Date
    let sets: [(weight: Double, reps: Int)]

    var best: (weight: Double, reps: Int)? {
        sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
    }

    /// Workouts and quick logs together, newest first.
    static func all(for id: String, sessions: [WorkoutSession], logs: [ExerciseLog]) -> [ExerciseHistoryEntry] {
        let fromWorkouts = sessions.compactMap { s -> ExerciseHistoryEntry? in
            let sets = s.exercises.filter { $0.exerciseID == id }.flatMap(\.sets).filter(\.completed)
                .map { (weight: $0.weight, reps: $0.reps) }
            return sets.isEmpty ? nil : ExerciseHistoryEntry(date: s.startedAt, sets: sets)
        }
        let fromLogs = logs.compactMap { l -> ExerciseHistoryEntry? in
            let sets = l.sets.map { (weight: $0.weightKg, reps: $0.reps) }.filter { $0.reps > 0 }
            return sets.isEmpty ? nil : ExerciseHistoryEntry(date: l.date, sets: sets)
        }
        return (fromWorkouts + fromLogs).sorted { $0.date > $1.date }
    }
}

private struct ExerciseHistory: View {
    let exercise: Exercise
    let entries: [ExerciseHistoryEntry]

    private func kg(_ v: Double) -> String {
        String(format: v == v.rounded() ? "%.0f" : "%.1f", locale: .current, v)
    }

    private func setText(_ s: (weight: Double, reps: Int)) -> String {
        s.weight > 0 ? "\(kg(s.weight)) kg × \(s.reps)" : "\(s.reps) " + EXL("Reps").lowercased()
    }

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(.sbBorder)
                Text(EXL("No logs yet"))
                    .font(SBFont.heading(17))
                    .foregroundColor(.sbTextSecondary)
                Text(EXL("Log this exercise to start tracking your progress."))
                    .font(SBFont.body(14))
                    .foregroundColor(.sbTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                record
                weeklyChart
                lastSession
            }
        }
    }

    // Best set ever, and how much it beats the first one.
    private var record: some View {
        let all = entries.compactMap(\.best)
        let top = all.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }!
        let first = entries.last?.best
        let gain = first.map { top.weight - $0.weight } ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(12)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: setText(top))
                    .font(SBFont.heading(20))
                    .foregroundColor(.sbTextPrimary)
                Text("exercise.history.record")
                    .font(SBFont.label(11))
                    .foregroundColor(.sbTextSecondary)
            }
            Spacer()
            if gain > 0 {
                Text(verbatim: "+\(kg(gain)) kg")
                    .font(SBFont.label(12))
                    .foregroundColor(.sbGreen)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.sbGreen.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(13)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    /// Best weight of each of the last six weeks (reps for bodyweight moves).
    private var weeklyChart: some View {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weeks = (0..<6).reversed().compactMap { cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        let bodyweight = entries.allSatisfy { $0.best?.weight ?? 0 == 0 }
        let values: [Double] = weeks.map { start in
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return entries.filter { $0.date >= start && $0.date < end }
                .compactMap(\.best).map { bodyweight ? Double($0.reps) : $0.weight }.max() ?? 0
        }
        let top = max(values.max() ?? 1, 1)
        let dayMonth = DateFormatter()
        dayMonth.setLocalizedDateFormatFromTemplate("d/M")
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("exercise.history.weekly").font(SBFont.heading(13)).foregroundColor(.sbTextPrimary)
                Spacer()
                Text(verbatim: bodyweight ? EXL("Reps").lowercased() : "kg")
                    .font(SBFont.label(11)).foregroundColor(.sbTextSecondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(values[i] > 0
                                  ? AnyShapeStyle(LinearGradient(colors: [.sbAccent, .sbCyan], startPoint: .bottom, endPoint: .top))
                                  : AnyShapeStyle(Color.sbSurfaceRaised))
                            .frame(height: max(8, 80 * values[i] / top))
                        Text(verbatim: i == values.count - 1
                             ? NSLocalizedString("exercise.history.thisWeek", comment: "")
                             : dayMonth.string(from: weeks[i]))
                            .font(SBFont.label(9))
                            .foregroundColor(.sbTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
        .padding(13)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    /// The last time, set by set, and what the progression engine wants next.
    private var lastSession: some View {
        let last = entries[0]
        let target = Int(exercise.defaultReps.prefix { $0.isNumber }) ?? 8
        let next = ProgressionEngine.suggestion(for: exercise.id, history: WorkoutStore.shared.history,
                                                targetReps: target, fallbackWeight: 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: String(format: NSLocalizedString("exercise.history.last", comment: ""), locale: .current,
                                  last.date.formatted(.dateTime.day().month(.abbreviated))).uppercased())
                .font(SBFont.label(11))
                .tracking(0.8)
                .foregroundColor(.sbAccent)
            FlowRow(spacing: 6) {
                ForEach(Array(last.sets.enumerated()), id: \.offset) { _, s in
                    Text(verbatim: setText(s))
                        .font(SBFont.label(12))
                        .foregroundColor(.sbTextPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.sbSurfaceRaised)
                        .cornerRadius(9)
                }
            }
            if next.reason != .firstTime, next.weight > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.sbGreen)
                    Text("exercise.history.next")
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)
                    Text(verbatim: "\(kg(next.weight)) kg × \(next.reps)")
                        .font(SBFont.heading(13))
                        .foregroundColor(.sbGreen)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }
}

// MARK: - Log Exercise Sheet

struct LogExerciseSheet: View {
    let exercise: Exercise
    @Binding var isPresented: Bool
    @State private var sets: [WorkoutSet] = [WorkoutSet(), WorkoutSet(), WorkoutSet()]

    var body: some View {
        ZStack {
            Color.sbBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sbBorder)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                HStack {
                    Text(verbatim: "\(EXL("Log")): \(EXL(exercise.name))")
                        .font(SBFont.heading(18))
                        .foregroundColor(.sbTextPrimary)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.sbBorder)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Column headers
                HStack {
                    Text(EXL("Set").uppercased()).font(SBFont.label(11)).foregroundColor(.sbTextSecondary).frame(width: 36)
                    Spacer()
                    Text(EXL("WEIGHT (kg)")).font(SBFont.label(11)).foregroundColor(.sbTextSecondary).frame(width: 110)
                    Spacer()
                    Text(EXL("Reps").uppercased()).font(SBFont.label(11)).foregroundColor(.sbTextSecondary).frame(width: 70)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                Divider().background(Color.sbBorder).padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sets.indices, id: \.self) { i in
                            SetRow(index: i, set: $sets[i])
                            Divider().background(Color.sbBorder).padding(.horizontal, 20)
                        }
                    }
                }

                // Add Set
                Button {
                    sets.append(WorkoutSet())
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(EXL("Add Set"))
                    }
                    .font(SBFont.body())
                    .foregroundColor(.sbAccent)
                    .padding(.vertical, 14)
                }

                SBPrimaryButton(title: EXL("Save Log")) {
                    ExerciseLogStore.shared.save(ExerciseLog(exerciseId: exercise.id, sets: sets))
                    isPresented = false
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SetRow: View {
    let index: Int
    @Binding var set: WorkoutSet

    var body: some View {
        HStack {
            Text("\(index + 1)")
                .font(SBFont.heading(16))
                .foregroundColor(.sbTextSecondary)
                .frame(width: 36)

            Spacer()

            // Weight stepper
            HStack(spacing: 0) {
                StepButton(icon: "minus") {
                    if set.weightKg >= 2.5 { set.weightKg -= 2.5 }
                }
                Text(verbatim: set.weightKg > 0 ? String(format: "%.1f", set.weightKg) : NSLocalizedString("BW", comment: ""))
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                    .frame(width: 60)
                StepButton(icon: "plus") { set.weightKg += 2.5 }
            }
            .background(Color.sbSurface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sbBorder))
            .frame(width: 110)

            Spacer()

            // Reps stepper
            HStack(spacing: 0) {
                StepButton(icon: "minus") { if set.reps > 1 { set.reps -= 1 } }
                Text("\(set.reps)")
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                    .frame(width: 36)
                StepButton(icon: "plus") { set.reps += 1 }
            }
            .background(Color.sbSurface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sbBorder))
            .frame(width: 70)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct StepButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.sbTextSecondary)
                .frame(width: 30, height: 36)
                .contentShape(Rectangle())
        }
    }
}
