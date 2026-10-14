import SwiftUI

struct AICoachView: View {
    /// True when this is the plan reveal right after onboarding: the screen is
    /// then the app's root, so it finishes with "Start" instead of a close X.
    var isFirstReveal: Bool = false
    /// Called when the user finishes the first reveal.
    var onFinishReveal: (() -> Void)? = nil

    @ObservedObject private var profile  = UserProfile.shared
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var planStore = PlanStore.shared

    @State private var extraContext = ""
    @State private var isGenerating = false
    /// "New plan" shows the form over the current plan instead of deleting
    /// it: the old plan carries the coach's memory (cycle week, calorie
    /// adjustment), and the next plan needs it.
    @State private var editing = false
    @State private var selectedDay: DayPlan?
    /// Day shown in the menu; nil = today.
    @State private var menuDay: Int?
    @State private var openRecipe: PlannedRecipe?

    /// The plan comes from the store, so it survives leaving this screen and
    /// relaunching the app.
    private var plan: FitnessPlan? { planStore.plan }

    var body: some View {
        ZStack {
            Color.sbBackground.ignoresSafeArea()
            if isGenerating                  { loadingView }
            else if let p = plan, !editing   { planView(p) }
            else                             { setupView  }
        }
        .sheet(item: $selectedDay) { DayDetailSheet(day: $0) }
        .sheet(item: $openRecipe) { RecipeDetailView(recipe: $0.recipe, initialServings: $0.servings) }
    }

    // MARK: - Setup

    private var setupView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Top bar
                HStack {
                    Button {
                        if editing { withAnimation(.easeInOut) { editing = false } } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.sbTextSecondary)
                            .frame(width: 34, height: 34)
                            .background(Color.sbSurface)
                            .clipShape(Circle())
                    }
                    Spacer()
                }

                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.sbAccent.opacity(0.15))
                            .frame(width: 90, height: 90)
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.sbAccent)
                    }
                    Text("PowerPump Coach")
                        .font(SBFont.display(28))
                        .foregroundColor(.sbTextPrimary)
                    Text(LocalizedStringKey(CoachL.subtitle))
                        .font(SBFont.body())
                        .foregroundColor(.sbTextSecondary)
                        .multilineTextAlignment(.center)
                }

                // Profile summary card
                profileCard

                // Extra context
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(CoachL.extraContextLabel))
                        .font(SBFont.caption())
                        .foregroundColor(.sbTextSecondary)

                    TextField(CoachL.extraContextPlaceholder,
                              text: $extraContext, axis: .vertical)
                        .lineLimit(3...6)
                        .font(SBFont.body())
                        .foregroundColor(.sbTextPrimary)
                        .padding(14)
                        .background(Color.sbSurface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
                }

                // Generate button
                Button { generate() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(LocalizedStringKey(CoachL.buildMyPlan))
                            .fontWeight(.bold)
                    }
                    .font(SBFont.body())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.sbAccent)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        // Show what the user wrote last time (a bad knee, training at home…)
        // instead of an empty box: the weekly automatic plan still uses it.
        .onAppear { if extraContext.isEmpty { extraContext = planStore.extraContext } }
    }

    // MARK: - Profile summary

    private var profileCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label(LocalizedStringKey(CoachL.yourProfile), systemImage: "person.fill")
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                Text(LocalizedStringKey(CoachL.editInProfile))
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
            }
            Divider().background(Color.sbBorder)
            HStack(spacing: 0) {
                profileStat(CoachL.goal,     profile.goal.rawValue)
                Divider().frame(height: 36)
                profileStat(CoachL.activity, shortActivity(profile.activityLevel))
                Divider().frame(height: 36)
                profileStat(CoachL.calories, "\(profile.dailyCalorieTarget) kcal")
                Divider().frame(height: 36)
                profileStat(CoachL.protein,  "\(profile.dailyProteinTarget) g")
            }
        }
        .padding(14)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    private func profileStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(value))
                .font(SBFont.label(11))
                .fontWeight(.bold)
                .foregroundColor(.sbAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(SBFont.label(9))
                .foregroundColor(.sbTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func shortActivity(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return CoachL.sedentary
        case .light:     return CoachL.light
        case .moderate:  return CoachL.moderate
        case .active:    return CoachL.active
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(Color.sbAccent.opacity(0.1)).frame(width: 100, height: 100)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.sbAccent)
            }
            VStack(spacing: 8) {
                Text(LocalizedStringKey(CoachL.buildingPlan))
                    .font(SBFont.heading())
                    .foregroundColor(.sbTextPrimary)
                Text(LocalizedStringKey(CoachL.personalisingPlan))
                    .font(SBFont.body())
                    .foregroundColor(.sbTextSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Plan view

    private func planView(_ p: FitnessPlan) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Top bar — on the first reveal there is nothing to dismiss to,
                // so the close button and "new plan" are hidden.
                if !isFirstReveal {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.sbTextSecondary)
                                .frame(width: 34, height: 34)
                                .background(Color.sbSurface)
                                .clipShape(Circle())
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeInOut) { editing = true }
                        } label: {
                            Label(LocalizedStringKey(CoachL.newPlan), systemImage: "arrow.clockwise")
                                .font(SBFont.caption())
                                .foregroundColor(.sbAccent)
                        }
                    }
                } else {
                    firstRevealHeader
                }

                motivationBanner(p.motivation)
                if let report = p.report { reportCard(report) }
                analysisCard(p.analysis)
                weeklySection(p.weeklySchedule)
                nutritionSection(p.nutritionPlan,
                                 variesByDay: p.weeklyMeals.contains { $0.target != nil })
                if !p.weeklyMeals.isEmpty { menuSection(p.weeklyMeals) }
                if !p.tips.isEmpty { tipsSection(p.tips) }
                SourcesLink()
                    .frame(maxWidth: .infinity)

                if isFirstReveal {
                    SBPrimaryButton(title: EXL("Start training")) {
                        HapticManager.heavy()
                        onFinishReveal?()
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 80)
            }
            .padding(20)
        }
    }

    // MARK: - Plan sub-views

    /// Shown instead of the toolbar the first time: frames the plan as the
    /// payoff for the questionnaire the user just filled in.
    private var firstRevealHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.sbAccent.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.sbAccent)
            }
            Text(EXL("Your plan is ready"))
                .font(SBFont.display(26))
                .foregroundColor(.sbTextPrimary)
                .multilineTextAlignment(.center)
            Text(EXL("Built from your goal, your body and the sport you practice."))
                .font(SBFont.body())
                .foregroundColor(.sbTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func motivationBanner(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(text)
                .font(SBFont.body())
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbAccent)
        .cornerRadius(16)
    }

    private func analysisCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalizedStringKey(CoachL.planOverview), systemImage: "doc.text.fill")
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)
            Text(text)
                .font(SBFont.body())
                .foregroundColor(.sbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    private func weeklySection(_ schedule: [DayPlan]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(CoachL.sevenDaySchedule))
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(schedule) { DayPill(day: $0) }
                }
                .padding(.horizontal, 2)
            }

            VStack(spacing: 10) {
                ForEach(schedule) { day in
                    Button { selectedDay = day } label: { DayRow(day: day) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func nutritionSection(_ n: AINutritionPlan, variesByDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(CoachL.nutritionTargets))
                    .font(SBFont.heading())
                    .foregroundColor(.sbTextPrimary)
                // With carb cycling these are the week's average, not every
                // day's number — say so, or a heavy day looks like a mistake.
                if variesByDay {
                    Text("coach.ui.weeklyAverage")
                        .font(SBFont.label(11)).foregroundColor(.sbAccent).textCase(.uppercase)
                    Text("coach.ui.variesByDay")
                        .font(SBFont.caption()).foregroundColor(.sbTextSecondary)
                }
            }

            HStack(spacing: 0) {
                nutritionStat(CoachL.calories, "\(n.calories)", "kcal")
                Divider().frame(height: 40)
                nutritionStat(CoachL.protein,  "\(n.protein)",  "g")
                Divider().frame(height: 40)
                nutritionStat(CoachL.carbs,    "\(n.carbs)",    "g")
                Divider().frame(height: 40)
                nutritionStat(CoachL.fat,      "\(n.fat)",      "g")
            }
            .padding(14)
            .background(Color.sbSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))

            if !n.tips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(n.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "fork.knife.circle.fill")
                                .foregroundColor(.sbAccent).font(.system(size: 16))
                            Text(tip).font(SBFont.body()).foregroundColor(.sbTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .background(Color.sbSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
            }
        }
    }

    private func tipsSection(_ tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(CoachL.coachTips))
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.sbAccent).font(.system(size: 14)).padding(.top, 3)
                        Text(tip).font(SBFont.body()).foregroundColor(.sbTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(Color.sbSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
        }
    }

    // MARK: - Coach report

    /// What the coach read from the last week and what it changed because of
    /// it — the part that makes the plan feel like it's paying attention.
    private func reportCard(_ r: CoachReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(LocalizedStringKey("coach.ui.yourWeek"), systemImage: "chart.line.uptrend.xyaxis")
                    .font(SBFont.heading())
                    .foregroundColor(.sbTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(verbatim: String(format: NSLocalizedString("coach.ui.blockWeek", comment: ""), r.blockWeek))
                    .font(SBFont.label(11))
                    .foregroundColor(r.volume == .deload ? .orange : .sbAccent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill((r.volume == .deload ? Color.orange : .sbAccent).opacity(0.15)))
            }

            HStack(spacing: 8) {
                reportStat(icon: "dumbbell.fill", label: "Workouts",
                           value: r.sessionsPlanned.map { "\(r.sessionsDone)/\($0)" } ?? "\(r.sessionsDone)")
                reportStat(icon: "scalemass.fill", label: "Weight",
                           value: r.weightRate.map { String(format: "%+.1f", $0) } ?? "—",
                           unit: r.weightRate == nil ? nil : NSLocalizedString("coach.ui.perWeek", comment: ""))
                reportStat(icon: "fork.knife", label: "coach.ui.avgIntake",
                           value: r.avgCalories.map { "\($0)" } ?? "—",
                           unit: r.avgCalories == nil ? nil : "kcal")
            }

            if !r.notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(r.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.sbAccent)
                                .padding(.top, 4)
                            Text(verbatim: note)
                                .font(SBFont.body(14))
                                .foregroundColor(.sbTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.35)))
    }

    private func reportStat(icon: String, label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.sbAccent)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(SBFont.heading(17))
                    .foregroundColor(.sbTextPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(verbatim: unit).font(SBFont.label(9)).foregroundColor(.sbTextSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(LocalizedStringKey(label))
                .font(SBFont.label(10))
                .foregroundColor(.sbTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.sbSurfaceRaised)
        .cornerRadius(12)
    }

    // MARK: - Menu

    /// One day's meals at a time, with portions and macros, picked from a row
    /// of days — seven full menus stacked would be a wall of text.
    private func menuSection(_ days: [DayMeals]) -> some View {
        let sel = min(max(menuDay ?? planStore.todayIndex ?? 0, 0), days.count - 1)
        let day = days[sel]
        return VStack(alignment: .leading, spacing: 12) {
            Text("coach.ui.menu")
                .font(SBFont.heading())
                .foregroundColor(.sbTextPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { menuDay = i }
                        } label: {
                            VStack(spacing: 5) {
                                Text(verbatim: String(d.day.prefix(3)))
                                    .font(SBFont.label(11))
                                Circle()
                                    .fill(i == sel ? Color.white : (d.intensity ?? .rest).tint)
                                    .frame(width: 6, height: 6)
                            }
                            .foregroundColor(i == sel ? .white : .sbTextSecondary)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(i == sel ? Color.sbAccent : Color.sbSurface))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if let meals = day.meals, !meals.isEmpty {
                VStack(spacing: 0) {
                    menuHeader(day)
                    ForEach(meals) { meal in
                        Divider().background(Color.sbBorder)
                        mealRow(meal)
                    }
                    if let tot = day.totals {
                        Divider().background(Color.sbBorder)
                        menuTotals(tot)
                    }
                }
                .background(Color.sbSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
            } else {
                // Plans saved before portions existed: just the dish names.
                VStack(alignment: .leading, spacing: 8) {
                    legacyMealLine(icon: "sunrise.fill", name: day.breakfast)
                    legacyMealLine(icon: "sun.max.fill", name: day.lunch)
                    legacyMealLine(icon: "moon.fill",    name: day.dinner)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sbSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
            }
        }
    }

    private func menuHeader(_ day: DayMeals) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: day.day)
                .font(SBFont.heading(15))
                .foregroundColor(.sbTextPrimary)
            if let intensity = day.intensity {
                IntensityBadge(intensity: intensity)
            }
            Spacer()
            if let t = day.target {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: "\(t.kcal) kcal")
                        .font(SBFont.heading(14))
                        .foregroundColor(.sbTextPrimary)
                    Text("coach.ui.target")
                        .font(SBFont.label(9))
                        .foregroundColor(.sbTextSecondary)
                }
            }
        }
        .padding(14)
    }

    private func mealRow(_ m: PlannedMeal) -> some View {
        let recipe = m.recipeID.flatMap { id in RecipeDatabase.all.first { $0.id == id } }
        return Button {
            if let recipe { openRecipe = PlannedRecipe(recipe: recipe, servings: m.servings ?? 1) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: m.slot.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.sbAccent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.sbAccentDim))
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(m.slot.labelKey))
                        .font(SBFont.label(10))
                        .foregroundColor(.sbTextSecondary)
                        .textCase(.uppercase)
                    if m.recipeID == nil, let items = m.items {
                        // Food combinations: every component with its grams.
                        Text(verbatim: itemsText(items))
                            .font(SBFont.body(14))
                            .foregroundColor(.sbTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(LocalizedStringKey(m.name))
                            .font(SBFont.body(15))
                            .foregroundColor(.sbTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: servingsText(m.servings ?? 1))
                            .font(SBFont.caption())
                            .foregroundColor(.sbAccent)
                        // Protein side added by the planner (seitan, chicken…).
                        if let side = m.items, !side.isEmpty {
                            Text(verbatim: "+ " + itemsText(side))
                                .font(SBFont.caption())
                                .foregroundColor(.sbTextSecondary)
                        }
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(m.kcal)")
                        .font(SBFont.heading(15))
                        .foregroundColor(.sbTextPrimary)
                        .monospacedDigit()
                    Text(verbatim: "kcal · P \(m.protein) g")
                        .font(SBFont.label(9))
                        .foregroundColor(.sbTextSecondary)
                }
                if recipe != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.sbTextSecondary.opacity(0.5))
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that greys the row out, and a snack isn't
        // unavailable — it just has no recipe to open.
        .allowsHitTesting(recipe != nil)
    }

    private func menuTotals(_ t: MacroTarget) -> some View {
        HStack(spacing: 0) {
            Text("coach.ui.total")
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary)
                .textCase(.uppercase)
            Spacer()
            Text(verbatim: "\(t.kcal) kcal  ·  P \(t.protein)  ·  C \(t.carbs)  ·  G \(t.fat)")
                .font(SBFont.caption())
                .foregroundColor(.sbTextPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
    }

    private func itemsText(_ items: [PlannedFood]) -> String {
        items.map { NSLocalizedString($0.name, comment: "") + " \($0.grams) g" }.joined(separator: " · ")
    }

    /// "1 serving", "1½ servings" — quarters as fractions read more naturally
    /// than 1.25 on a menu.
    private func servingsText(_ s: Double) -> String {
        if s == 1 { return NSLocalizedString("coach.ui.serving", comment: "") }
        let whole = Int(s)
        let frac: String
        switch s - Double(whole) {
        case 0.25: frac = "¼"
        case 0.5:  frac = "½"
        case 0.75: frac = "¾"
        default:   frac = ""
        }
        let number = (whole > 0 ? "\(whole)" : "") + frac
        return String(format: NSLocalizedString("coach.ui.servings", comment: ""), number)
    }

    private func legacyMealLine(icon: String, name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.sbTextSecondary)
                .frame(width: 16)
            Text(LocalizedStringKey(name))
                .font(SBFont.body(14))
                .foregroundColor(.sbTextPrimary)
        }
    }

    private func nutritionStat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(SBFont.heading(18)).foregroundColor(.sbTextPrimary)
                Text(unit).font(SBFont.label()).foregroundColor(.sbTextSecondary)
            }
            Text(label).font(SBFont.label(10)).foregroundColor(.sbTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Generate (local — no API)

    private func generate() {
        isGenerating = true
        // Read the stores now, before the delay, so the plan reflects the
        // moment the user tapped.
        let inputs = CoachInputs.current(extraContext: extraContext)

        // Brief delay for UX feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                planStore.generate(inputs: inputs)
                isGenerating = false
                editing = false
            }
        }
    }
}

// MARK: - Day Pill

private struct DayPill: View {
    let day: DayPlan
    var body: some View {
        let intensity = day.intensity
        VStack(spacing: 6) {
            Text(String(day.day.prefix(3)))
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary)
            ZStack {
                Circle()
                    .fill(day.isActive ? (intensity?.tint ?? .sbAccent) : Color.sbSurface)
                    .frame(width: 38, height: 38)
                Image(systemName: day.symbol ?? (day.isWorkout ? "dumbbell.fill" : "moon.zzz.fill"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(day.isActive ? .white : .sbTextSecondary)
            }
        }
    }
}

// MARK: - Day Row

private struct DayRow: View {
    let day: DayPlan
    var body: some View {
        let tint = day.isActive ? (day.intensity?.tint ?? .sbAccent) : Color.sbTextSecondary
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(day.isActive ? tint.opacity(0.15) : Color.sbSurface)
                    .frame(width: 46, height: 46)
                Image(systemName: day.symbol ?? (day.isWorkout ? "dumbbell.fill" : "moon.zzz.fill"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(day.day).font(SBFont.heading(15)).foregroundColor(.sbTextPrimary)
                    Spacer()
                    if let intensity = day.intensity {
                        IntensityBadge(intensity: intensity)
                    } else {
                        // Plans from before intensities: the old workout/rest tag.
                        Text(LocalizedStringKey(day.isWorkout ? CoachL.workout : CoachL.rest))
                            .font(SBFont.label(10))
                            .foregroundColor(day.isWorkout ? .sbAccent : .sbTextSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(day.isWorkout ? Color.sbAccent.opacity(0.12) : Color.sbSurfaceRaised)
                            .cornerRadius(6)
                    }
                }
                Text(day.focus).font(SBFont.caption()).foregroundColor(.sbTextSecondary).lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12)).foregroundColor(.sbBorder)
        }
        .padding(12)
        .background(Color.sbSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
    }
}

// MARK: - Day Detail Sheet

struct DayDetailSheet: View {
    let day: DayPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(day.isActive ? (day.intensity?.tint ?? .sbAccent) : Color.sbSurface)
                                    .frame(width: 56, height: 56)
                                Image(systemName: day.symbol ?? (day.isWorkout ? "dumbbell.fill" : "moon.zzz.fill"))
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(day.isActive ? .white : .sbTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(day.day).font(SBFont.heading(20)).foregroundColor(.sbTextPrimary)
                                    if let intensity = day.intensity { IntensityBadge(intensity: intensity) }
                                }
                                Text(day.focus).font(SBFont.body()).foregroundColor(.sbTextSecondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sbSurface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))

                        Text(LocalizedStringKey(day.isWorkout ? CoachL.exercises : CoachL.recovery))
                            .font(SBFont.heading())
                            .foregroundColor(.sbTextPrimary)

                        VStack(spacing: 10) {
                            ForEach(Array(day.exercises.enumerated()), id: \.offset) { i, ex in
                                HStack(spacing: 14) {
                                    Text("\(i + 1)")
                                        .font(SBFont.label())
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(day.isWorkout ? Color.sbAccent : Color.sbTextSecondary)
                                        .clipShape(Circle())
                                    Text(verbatim: EXLPlanLine(ex))
                                        .font(SBFont.body()).foregroundColor(.sbTextPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                                .padding(14)
                                .background(Color.sbSurface)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sbBorder))
                            }
                        }
                        // Explain the numbers the plan now carries.
                        if day.exercises.contains(where: { $0.contains("RPE") }) {
                            loadNote("gauge.with.dots.needle.67percent", "coach.ui.rpe")
                        }
                        if day.exercises.contains(where: { $0.hasSuffix(" kg") }) {
                            loadNote("chart.line.uptrend.xyaxis", "coach.ui.kgNote")
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(day.day)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CoachL.done) { dismiss() }.foregroundColor(.sbAccent)
                }
            }
        }
    }
}

// MARK: - Intensity & meals UI

private extension DayDetailSheet {
    func loadNote(_ icon: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.sbAccent)
                .padding(.top, 2)
            Text(LocalizedStringKey(key))
                .font(SBFont.caption())
                .foregroundColor(.sbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbAccentDim)
        .cornerRadius(12)
    }
}

extension DayIntensity {
    var tint: Color {
        switch self {
        case .heavy:  return .sbAccent
        case .medium: return Color(hex: "#5E9EFF")
        case .light:  return .sbCyan
        case .deload: return .orange
        case .rest:   return .sbTextSecondary
        case .sport:  return .sbGreen
        }
    }

    var icon: String {
        switch self {
        case .heavy:  return "flame.fill"
        case .medium: return "dumbbell.fill"
        case .light:  return "wind"
        case .deload: return "arrow.down.circle.fill"
        case .rest:   return "moon.zzz.fill"
        case .sport:  return "trophy.fill"
        }
    }
}

extension DayPlan {
    /// Gym or the user's own sport: shown in colour, not as a grey rest day.
    var isActive: Bool { isWorkout || intensity == .sport }
    /// The sport's own symbol on practice days (a BJJ class shows a martial
    /// artist, not a generic trophy).
    var symbol: String? {
        if intensity == .sport, let id = sport, let s = SportLibrary.byID(id) { return s.icon }
        return intensity?.icon
    }
}

extension PlannedMeal.MealSlot {
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .snack:     return "leaf.fill"
        case .dinner:    return "moon.fill"
        }
    }
}

/// "Heavy" / "Light" / … pill in the day's colour.
struct IntensityBadge: View {
    let intensity: DayIntensity
    var body: some View {
        Text(LocalizedStringKey(intensity.labelKey))
            .font(SBFont.label(10))
            .foregroundColor(intensity.tint)
            .textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(intensity.tint.opacity(0.14))
            .cornerRadius(6)
    }
}

/// A planned meal opened as its recipe, at the planned portion.
private struct PlannedRecipe: Identifiable {
    let recipe: Recipe
    let servings: Double
    var id: String { recipe.id }
}

// MARK: - Localization helper

private enum CoachL {
    private static var lang: String { LanguageManager.shared.selectedCode }

    static var subtitle: String {
        switch lang {
        case "es":    return "Describe tu estado actual y objetivo. Tu coach generará un plan personalizado de 7 días al instante."
        case "it":    return "Descrivi il tuo stato attuale e l'obiettivo. Il tuo coach genererà un piano personalizzato di 7 giorni all'istante."
        case "pt-BR": return "Descreva seu estado atual e objetivo. Seu coach gerará um plano personalizado de 7 dias instantaneamente."
        case "fr":    return "Décris ton état actuel et ton objectif. Ton coach générera un plan personnalisé de 7 jours instantanément."
        default:      return "Describe your current state and any specific goal. Your coach will generate a personalised 7-day plan instantly."
        }
    }
    static var extraContextLabel: String {
        switch lang {
        case "es":    return "¿Algo más a considerar? (opcional)"
        case "it":    return "Altro da considerare? (opzionale)"
        case "pt-BR": return "Mais alguma coisa a considerar? (opcional)"
        case "fr":    return "Autre chose à prendre en compte ? (facultatif)"
        default:      return "Anything else to consider? (optional)"
        }
    }
    static var extraContextPlaceholder: String {
        switch lang {
        case "es":    return "Ej. tengo mala rodilla, prefiero ejercicios en casa, solo puedo entrenar de mañana…"
        case "it":    return "Es. ho un ginocchio dolorante, preferisco esercizi a casa, mi alleno solo al mattino…"
        case "pt-BR": return "Ex. tenho dor no joelho, prefiro treinos em casa, só posso treinar de manhã…"
        case "fr":    return "Ex. j'ai un genou douloureux, je préfère m'entraîner à la maison, seulement le matin…"
        default:      return "e.g. I have a bad knee, prefer home workouts, can train mornings only…"
        }
    }
    static var buildMyPlan: String {
        switch lang {
        case "es":    return "Crear mi Plan"
        case "it":    return "Crea il mio Piano"
        case "pt-BR": return "Criar meu Plano"
        case "fr":    return "Créer mon Plan"
        default:      return "Build My Plan"
        }
    }
    static var yourProfile: String {
        switch lang {
        case "es":    return "Tu Perfil"
        case "it":    return "Il tuo Profilo"
        case "pt-BR": return "Seu Perfil"
        case "fr":    return "Ton Profil"
        default:      return "Your Profile"
        }
    }
    static var editInProfile: String {
        switch lang {
        case "es":    return "Editar en Perfil"
        case "it":    return "Modifica nel Profilo"
        case "pt-BR": return "Editar no Perfil"
        case "fr":    return "Modifier dans Profil"
        default:      return "Edit in Profile tab"
        }
    }
    static var goal:     String { switch lang { case "es": return "Objetivo"; case "it": return "Obiettivo"; case "pt-BR": return "Objetivo"; case "fr": return "Objectif"; default: return "Goal" } }
    static var activity: String { switch lang { case "es": return "Actividad"; case "it": return "Attività";  case "pt-BR": return "Atividade"; case "fr": return "Activité"; default: return "Activity" } }
    static var calories: String { switch lang { case "es": return "Calorías"; case "it": return "Calorie";   case "pt-BR": return "Calorias";  case "fr": return "Calories"; default: return "Calories" } }
    static var protein:  String { switch lang { case "es": return "Proteína"; case "it": return "Proteine";  case "pt-BR": return "Proteína";  case "fr": return "Protéines"; default: return "Protein" } }
    static var carbs:    String { switch lang { case "es": return "Carbos";   case "it": return "Carboidrati"; case "pt-BR": return "Carbos";  case "fr": return "Glucides"; default: return "Carbs" } }
    static var fat:      String { switch lang { case "es": return "Grasa";    case "it": return "Grassi";    case "pt-BR": return "Gordura";   case "fr": return "Lipides"; default: return "Fat" } }
    static var buildingPlan: String {
        switch lang {
        case "es":    return "Creando tu plan…"
        case "it":    return "Creando il tuo piano…"
        case "pt-BR": return "Criando seu plano…"
        case "fr":    return "Création de ton plan…"
        default:      return "Building your plan…"
        }
    }
    static var personalisingPlan: String {
        switch lang {
        case "es":    return "Personalizando tu programa de 7 días"
        case "it":    return "Personalizzando il tuo programma di 7 giorni"
        case "pt-BR": return "Personalizando seu programa de 7 dias"
        case "fr":    return "Personnalisation de ton programme de 7 jours"
        default:      return "Personalising your 7-day programme"
        }
    }
    static var newPlan:         String { switch lang { case "es": return "Nuevo Plan"; case "it": return "Nuovo Piano"; case "pt-BR": return "Novo Plano"; case "fr": return "Nouveau Plan"; default: return "New Plan" } }
    static var planOverview:    String { switch lang { case "es": return "Resumen del Plan"; case "it": return "Panoramica del Piano"; case "pt-BR": return "Visão Geral do Plano"; case "fr": return "Vue d'ensemble"; default: return "Plan Overview" } }
    static var sevenDaySchedule: String { switch lang { case "es": return "Programa de 7 Días"; case "it": return "Programma di 7 Giorni"; case "pt-BR": return "Programa de 7 Dias"; case "fr": return "Programme de 7 Jours"; default: return "7-Day Schedule" } }
    static var nutritionTargets: String { switch lang { case "es": return "Objetivos Nutricionales"; case "it": return "Obiettivi Nutrizionali"; case "pt-BR": return "Metas Nutricionais"; case "fr": return "Objectifs Nutritionnels"; default: return "Nutrition Targets" } }
    static var coachTips:       String { switch lang { case "es": return "Consejos del Coach"; case "it": return "Consigli del Coach"; case "pt-BR": return "Dicas do Coach"; case "fr": return "Conseils du Coach"; default: return "Coach Tips" } }
    static var workout:         String { switch lang { case "es": return "Entrenamiento"; case "it": return "Allenamento"; case "pt-BR": return "Treino"; case "fr": return "Séance"; default: return "Workout" } }
    static var rest:            String { switch lang { case "es": return "Descanso"; case "it": return "Riposo"; case "pt-BR": return "Descanso"; case "fr": return "Repos"; default: return "Rest" } }
    static var exercises:       String { switch lang { case "es": return "Ejercicios"; case "it": return "Esercizi"; case "pt-BR": return "Exercícios"; case "fr": return "Exercices"; default: return "Exercises" } }
    static var recovery:        String { switch lang { case "es": return "Recuperación"; case "it": return "Recupero"; case "pt-BR": return "Recuperação"; case "fr": return "Récupération"; default: return "Recovery" } }
    static var done:            String { switch lang { case "es": return "Listo"; case "it": return "Fine"; case "pt-BR": return "Feito"; case "fr": return "Terminé"; default: return "Done" } }
    static var sedentary:       String { switch lang { case "es": return "Sedentario"; case "it": return "Sedentario"; case "pt-BR": return "Sedentário"; case "fr": return "Sédentaire"; default: return "Sedentary" } }
    static var light:           String { switch lang { case "es": return "Ligero"; case "it": return "Leggero"; case "pt-BR": return "Leve"; case "fr": return "Léger"; default: return "Light" } }
    static var moderate:        String { switch lang { case "es": return "Moderado"; case "it": return "Moderato"; case "pt-BR": return "Moderado"; case "fr": return "Modéré"; default: return "Moderate" } }
    static var active:          String { switch lang { case "es": return "Activo"; case "it": return "Attivo"; case "pt-BR": return "Ativo"; case "fr": return "Actif"; default: return "Active" } }
}

// MARK: - DayPlan Identifiable & Hashable

extension DayPlan: Hashable {
    static func == (lhs: DayPlan, rhs: DayPlan) -> Bool { lhs.day == rhs.day }
    func hash(into hasher: inout Hasher) { hasher.combine(day) }
}
