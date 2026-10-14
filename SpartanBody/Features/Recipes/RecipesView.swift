import SwiftUI

// MARK: - Groups

/// A shelf of recipes on the "For you" page, also usable as a filter.
enum RecipeShelf: String, CaseIterable, Hashable {
    case favorites, quick, breakfast, protein, mealPrep, plant

    var titleKey: String { "recipes.row." + rawValue }

    func contains(_ r: Recipe) -> Bool {
        switch self {
        case .favorites: return RecipeFavorites.shared.ids.contains(r.id)
        case .quick:     return r.prepMinutes <= 15
        case .breakfast: return r.tags.contains("Breakfast")
        case .protein:   return r.tags.contains("High Protein")
        case .mealPrep:  return r.tags.contains("Meal Prep")
        case .plant:     return r.tags.contains("Vegan") || r.tags.contains("Vegetarian")
        }
    }
}

/// Filter shown in the chips row.
enum RecipeFilter: Hashable {
    case forYou
    case goal(RecipeGoal)
    case shelf(RecipeShelf)

    var label: String {
        switch self {
        case .forYou:          return NSLocalizedString("recipes.forYou", comment: "")
        case .goal(let g):     return NSLocalizedString(g.rawValue, comment: "")
        case .shelf(.quick):   return NSLocalizedString("recipes.quick", comment: "")
        case .shelf(.plant):   return NSLocalizedString("recipes.plant", comment: "")
        case .shelf(.favorites): return NSLocalizedString("recipes.favorites", comment: "")
        case .shelf(let s):    return NSLocalizedString(s.titleKey, comment: "")
        }
    }
}

/// Recipes the user hearted, kept on this iPhone.
final class RecipeFavorites: ObservableObject {
    static let shared = RecipeFavorites()
    private let key = "sb_recipe_favorites"
    @Published private(set) var ids: Set<String>

    private init() { ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

// MARK: - List

struct RecipesView: View {
    @ObservedObject private var profile = UserProfile.shared
    @ObservedObject private var favorites = RecipeFavorites.shared
    @State private var selectedFilter: RecipeFilter = .forYou
    @State private var searchText = ""

    private var myGoal: RecipeGoal {
        switch profile.goal {
        case .gainMuscle: return .muscleGain
        case .loseWeight: return .weightLoss
        case .stayFit:    return .maintenance
        }
    }

    /// The user's own goal first, everywhere.
    private var ordered: [Recipe] {
        RecipeDatabase.all.filter { $0.goal == myGoal } + RecipeDatabase.all.filter { $0.goal != myGoal }
    }

    private var filters: [RecipeFilter] {
        var list: [RecipeFilter] = [.forYou, .goal(.weightLoss), .goal(.muscleGain), .goal(.maintenance),
                                    .shelf(.quick), .shelf(.plant)]
        if !favorites.ids.isEmpty { list.insert(.shelf(.favorites), at: 1) }
        return list
    }

    private var filtered: [Recipe] {
        var list = ordered
        switch selectedFilter {
        case .forYou:          break
        case .goal(let g):     list = list.filter { $0.goal == g }
        case .shelf(let s):    list = list.filter(s.contains)
        }
        if !searchText.isEmpty {
            // By dish or by ingredient, in either language.
            func has(_ s: String) -> Bool {
                s.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || NSLocalizedString(s, comment: "").range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            list = list.filter { r in has(r.name) || r.ingredients.contains { has($0.name) } }
        }
        return list
    }

    /// One recipe for your goal, a different one each day.
    private var featured: Recipe? {
        let mine = RecipeDatabase.all.filter { $0.goal == myGoal }
        guard !mine.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return mine[day % mine.count]
    }

    private var showsShelves: Bool { selectedFilter == .forYou && searchText.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        chips
                        if showsShelves {
                            shelves
                        } else if filtered.isEmpty {
                            emptyState
                        } else {
                            gridTitle
                            grid
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.top, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recipes")
                    .font(SBFont.display(28))
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                SourcesLink(compact: true)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.sbTextSecondary)
                TextField(NSLocalizedString("recipes.search", comment: ""), text: $searchText)
                    .font(SBFont.body())
                    .foregroundColor(.sbTextPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.sbTextSecondary)
                    }
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(12)
            .background(Color.sbSurface)
            .cornerRadius(13)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.sbBorder))
        }
        .padding(.horizontal, 20)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { f in
                    let on = selectedFilter == f
                    Button {
                        HapticManager.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = f }
                    } label: {
                        Text(verbatim: f.label)
                            .font(SBFont.caption())
                            .foregroundColor(on ? .white : .sbTextSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? Color.sbAccent : Color.sbSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(on ? Color.sbAccent : Color.sbBorder))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: For you

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let f = featured {
                NavigationLink(destination: RecipeDetailView(recipe: f, bottomInset: SBTabBar.overlapInset)) {
                    FeaturedRecipeCard(recipe: f)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
            ForEach(RecipeShelf.allCases, id: \.self) { shelf in
                let list = ordered.filter(shelf.contains).filter { $0.id != featured?.id }
                if list.count >= 2 { shelfRow(shelf, list) }
            }
        }
    }

    private func shelfRow(_ shelf: RecipeShelf, _ list: [Recipe]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: NSLocalizedString(shelf.titleKey, comment: ""))
                    .font(SBFont.heading(17))
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = .shelf(shelf) }
                } label: {
                    Text("recipes.seeAll").font(SBFont.caption()).foregroundColor(.sbAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(list.prefix(8)) { r in
                        NavigationLink(destination: RecipeDetailView(recipe: r, bottomInset: SBTabBar.overlapInset)) {
                            RecipeTile(recipe: r, artHeight: 110)
                                .frame(width: 148)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: Filtered

    /// What the grid is showing, since "See all" can pick a filter that has
    /// no chip in view.
    private var gridTitle: some View {
        let title: String
        if !searchText.isEmpty { title = NSLocalizedString("recipes.results", comment: "") }
        else if case .shelf(let shelf) = selectedFilter { title = NSLocalizedString(shelf.titleKey, comment: "") }
        else { title = selectedFilter.label }
        return HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .font(SBFont.heading(17))
                .foregroundColor(.sbTextPrimary)
            Spacer()
            Text(verbatim: String.localizedStringWithFormat(NSLocalizedString("recipes.count", comment: ""), filtered.count))
                .font(SBFont.caption())
                .foregroundColor(.sbTextSecondary)
        }
        .padding(.horizontal, 20)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  alignment: .leading, spacing: 16) {
            ForEach(filtered) { r in
                NavigationLink(destination: RecipeDetailView(recipe: r, bottomInset: SBTabBar.overlapInset)) {
                    RecipeTile(recipe: r, artHeight: 124)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundColor(.sbBorder)
            Text("No recipes found")
                .font(SBFont.heading(18))
                .foregroundColor(.sbTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// Localized "1 serving" / "N servings" for an integer serving count.
func servingsText(_ count: Int) -> String {
    let key = count == 1 ? "1 serving" : "%lld servings"
    return count == 1
        ? NSLocalizedString(key, comment: "")
        : String(format: NSLocalizedString(key, comment: ""), count)
}

// MARK: - Cards

/// The big card on top of "For you".
private struct FeaturedRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeArt(recipe: recipe, glyphSize: 58, glyphAlignment: .topTrailing)
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 6) {
                Text("recipes.featured")
                    .font(SBFont.label(11))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.9))
                Text(LocalizedStringKey(recipe.name))
                    .font(SBFont.heading(21))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    GlassPill(icon: "clock", text: "\(recipe.prepMinutes) min")
                    GlassPill(icon: "flame", text: "\(Int(recipe.nutrition.calories)) kcal")
                    GlassPill(icon: "bolt.fill", text: String(format: NSLocalizedString("recipes.proteinShort", comment: ""),
                                                              locale: .current, Int(recipe.nutrition.protein)))
                }
            }
            .padding(14)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct GlassPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(SBFont.label(11))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.18))
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25)))
    }
}

/// A recipe in a shelf or in the grid: picture, name, time and calories.
private struct RecipeTile: View {
    let recipe: Recipe
    let artHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipeArt(recipe: recipe, glyphSize: artHeight * 0.36)
                .frame(height: artHeight)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            Text(LocalizedStringKey(recipe.name))
                .font(SBFont.heading(13))
                .foregroundColor(.sbTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(recipe.prepMinutes) min · \(Int(recipe.nutrition.calories)) kcal")
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary)
        }
    }
}

// MARK: - Picture

/// The picture of a recipe: a colour for its kind of food and a line drawing
/// of the dish, in place of the old emoji.
struct RecipeArt: View {
    let recipe: Recipe
    var glyphSize: CGFloat = 48
    var glyphAlignment: Alignment = .center
    var glyphOffset: CGFloat = 0

    private var colors: [Color] {
        if recipe.tags.contains("Vegan") || recipe.tags.contains("Vegetarian") {
            return [Color(hex: "#6B3FD1"), Color(hex: "#BF5AF2"), Color(hex: "#F0A6FF")]
        }
        switch recipe.goal {
        case .weightLoss:  return [Color(hex: "#1F9D55"), Color(hex: "#34C759"), Color(hex: "#9BE15D")]
        case .muscleGain:  return [Color(hex: "#0A5BD8"), Color(hex: "#0A84FF"), Color(hex: "#32D5E8")]
        case .maintenance: return [Color(hex: "#D9480F"), Color(hex: "#FF9F0A"), Color(hex: "#FFD166")]
        }
    }

    var body: some View {
        ZStack(alignment: glyphAlignment) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.3, y: 0.2),
                           startRadius: 0, endRadius: 220)
            FoodGlyph(kind: FoodGlyph.Kind(for: recipe))
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.6, glyphSize / 18), lineCap: .round, lineJoin: .round))
                .frame(width: glyphSize, height: glyphSize)
                .padding(glyphAlignment == .center ? 0 : 18)
                .offset(y: glyphOffset)
        }
        .accessibilityHidden(true)
    }
}

/// Simple line drawings of dishes, drawn on a 24-point grid.
struct FoodGlyph: Shape {
    enum Kind {
        case salad, bowl, fish, egg, pot, wrap, jar

        init(for r: Recipe) {
            let id = r.id
            if id.contains("salmon") || id.contains("fish") { self = .fish }
            else if id.contains("soup") { self = .pot }
            else if id.contains("wrap") || id.contains("taco") { self = .wrap }
            else if id.contains("oats") || id.contains("yogurt") || id.contains("cottage") { self = .jar }
            else if id.contains("omelette") || id.contains("egg") || id.contains("frittata")
                        || id.contains("pancake") || id.contains("toast") { self = .egg }
            else if id.contains("salad") { self = .salad }
            else { self = .bowl }
        }
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()

        func bowl(rim y: CGFloat) {
            path.move(to: p(3, y))
            path.addLine(to: p(21, y))
            path.addArc(center: p(12, y), radius: 9 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }

        switch kind {
        case .bowl:
            bowl(rim: 11)
            path.move(to: p(8, 8)); path.addQuadCurve(to: p(13, 6), control: p(9.5, 5.5))
            path.move(to: p(12, 8)); path.addQuadCurve(to: p(17, 7), control: p(14.5, 5.5))
            path.move(to: p(9, 20)); path.addLine(to: p(15, 20))
        case .salad:
            bowl(rim: 12)
            path.move(to: p(8, 12)); path.addQuadCurve(to: p(12, 6), control: p(8, 8))
            path.move(to: p(12, 12)); path.addQuadCurve(to: p(17, 7), control: p(13, 8))
            path.move(to: p(7, 9)); path.addQuadCurve(to: p(11, 8), control: p(9, 7.5))
        case .fish:
            path.move(to: p(3, 12))
            path.addCurve(to: p(17, 9), control1: p(6, 7), control2: p(12, 6))
            path.addLine(to: p(21, 6))
            path.addLine(to: p(21, 18))
            path.addLine(to: p(17, 15))
            path.addCurve(to: p(3, 12), control1: p(12, 18), control2: p(6, 17))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: ox + 7 * s, y: oy + 10 * s, width: 2 * s, height: 2 * s))
        case .egg:
            path.addEllipse(in: CGRect(x: ox + 4 * s, y: oy + 6 * s, width: 14 * s, height: 14 * s))
            path.addEllipse(in: CGRect(x: ox + 8 * s, y: oy + 10 * s, width: 6 * s, height: 6 * s))
            path.move(to: p(17, 8)); path.addLine(to: p(21, 4))
        case .pot:
            path.addRoundedRect(in: CGRect(x: ox + 4 * s, y: oy + 10 * s, width: 16 * s, height: 10 * s),
                                cornerSize: CGSize(width: 3 * s, height: 3 * s))
            path.move(to: p(2, 10)); path.addLine(to: p(22, 10))
            path.move(to: p(9, 7)); path.addQuadCurve(to: p(9, 3), control: p(10.5, 5))
            path.move(to: p(13, 7)); path.addQuadCurve(to: p(13, 3), control: p(14.5, 5))
        case .wrap:
            path.move(to: p(4, 18))
            path.addCurve(to: p(12, 5), control1: p(4, 11), control2: p(8, 5))
            path.addCurve(to: p(20, 18), control1: p(16, 5), control2: p(20, 11))
            path.closeSubpath()
            path.move(to: p(8, 13)); path.addQuadCurve(to: p(16, 13), control: p(12, 15))
        case .jar:
            path.addRoundedRect(in: CGRect(x: ox + 7 * s, y: oy + 7 * s, width: 10 * s, height: 14 * s),
                                cornerSize: CGSize(width: 2 * s, height: 2 * s))
            path.addRect(CGRect(x: ox + 6 * s, y: oy + 4 * s, width: 12 * s, height: 3 * s))
            path.move(to: p(10, 12)); path.addLine(to: p(14, 12))
        }
        return path
    }
}

// MARK: - Recipe Detail

struct RecipeDetailView: View {
    let recipe: Recipe
    /// Opened from the coach's menu, the recipe starts at the planned portion
    /// so "Log" records what the plan actually said to eat.
    var initialServings: Double = 1
    /// Room for the floating tab bar when pushed inside the Recipes tab.
    var bottomInset: CGFloat = 0
    @ObservedObject private var foodLog = FoodLogStore.shared
    @ObservedObject private var favorites = RecipeFavorites.shared
    @State private var servings: Double = 1
    @State private var tab = 0
    @State private var scrollY: CGFloat = 0
    @State private var loggedMeal: MealType?
    @Environment(\.dismiss) private var dismiss

    private let heroHeight: CGFloat = 260
    private var collapsed: Bool { scrollY < -(heroHeight - 110) }
    private var scaled: NutritionInfo { recipe.nutrition.scaled(by: servings) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.sbBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 0) {
                        facts
                        macros
                        tabPicker
                        if tab == 0 { ingredients } else { steps }
                        fitCard
                        SourcesLink()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: DetailScrollKey.self, value: g.frame(in: .named("recipe")).minY)
                })
            }
            .coordinateSpace(name: "recipe")
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(DetailScrollKey.self) { scrollY = $0 }
            .modifier(ScrollOffsetReader(offset: $scrollY))
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }

            HStack {
                GlassCircleButton(icon: "chevron.left") { dismiss() }
                Spacer()
                GlassCircleButton(icon: favorites.ids.contains(recipe.id) ? "heart.fill" : "heart",
                                  label: LocalizedStringKey(favorites.ids.contains(recipe.id) ? "recipe.favorite.remove" : "recipe.favorite.add")) {
                    HapticManager.light()
                    favorites.toggle(recipe.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)

            DetailTopBar(title: NSLocalizedString(recipe.name, comment: ""), visible: collapsed) { dismiss() }

            if let meal = loggedMeal {
                toast(meal)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { servings = initialServings }
    }

    // MARK: Header

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeArt(recipe: recipe, glyphSize: 84, glyphOffset: -40)
            LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0),
                                   .init(color: .clear, location: 0.3),
                                   .init(color: .clear, location: 0.5),
                                   .init(color: .sbBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: eyebrow)
                    .font(SBFont.label(11))
                    .tracking(1.5)
                    .foregroundColor(.sbGreen)
                Text(LocalizedStringKey(recipe.name))
                    .font(SBFont.display(27))
                    .foregroundColor(.sbTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(height: heroHeight)
        .clipped()
    }

    /// "PERDER PESO · BAJO EN CALORÍAS"
    private var eyebrow: String {
        ([recipe.goal.rawValue] + recipe.tags.prefix(1))
            .map { NSLocalizedString($0, comment: "") }
            .joined(separator: " · ")
            .uppercased()
    }

    // MARK: Numbers

    private var facts: some View {
        HStack(spacing: 8) {
            FactCell(value: "\(Int(scaled.calories.rounded()))", label: "kcal")
            FactCell(value: "\(Int(scaled.protein.rounded())) g", label: NSLocalizedString("recipe.fact.protein", comment: ""))
            FactCell(value: "\(recipe.prepMinutes) min", label: NSLocalizedString("recipe.fact.time", comment: ""))
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// How the calories split between protein, carbs and fat.
    private var macros: some View {
        let p = scaled.protein * 4, c = scaled.carbs * 4, f = scaled.fat * 9
        let total = max(p + c + f, 1)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    Capsule().fill(Color.sbAccent).frame(width: max(4, (g.size.width - 4) * p / total))
                    Capsule().fill(Color.sbGreen).frame(width: max(4, (g.size.width - 4) * c / total))
                    Capsule().fill(Color.orange).frame(width: max(4, (g.size.width - 4) * f / total))
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                legend(.sbAccent, scaled.protein, "recipe.macro.protein")
                legend(.sbGreen, scaled.carbs, "recipe.macro.carbs")
                legend(.orange, scaled.fat, "recipe.macro.fat")
            }
        }
        .padding(.bottom, 16)
    }

    private func legend(_ color: Color, _ grams: Double, _ key: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(verbatim: "\(Int(grams.rounded())) g").font(SBFont.label(12)).foregroundColor(.sbTextPrimary)
            Text(verbatim: NSLocalizedString(key, comment: "")).font(SBFont.label(12)).foregroundColor(.sbTextSecondary)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            segment("Ingredients", 0)
            segment("Instructions", 1)
        }
        .padding(3)
        .background(Color.sbSurfaceRaised)
        .cornerRadius(12)
        .padding(.bottom, 14)
    }

    private func segment(_ title: LocalizedStringKey, _ index: Int) -> some View {
        Button {
            HapticManager.selection()
            withAnimation(.spring(response: 0.25)) { tab = index }
        } label: {
            Text(title)
                .font(SBFont.heading(14))
                .foregroundColor(tab == index ? .sbTextPrimary : .sbTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(tab == index ? Color.sbSurface : Color.clear)
                .cornerRadius(9)
                .shadow(color: .black.opacity(tab == index ? 0.2 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Tabs

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: String(format: NSLocalizedString("recipe.amountsFor", comment: ""), locale: .current,
                                  servingsText(recipe.servings)))
                .font(SBFont.caption())
                .foregroundColor(.sbTextSecondary)
            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { i, ing in
                    HStack(spacing: 10) {
                        Text(LocalizedStringKey(ing.name))
                            .font(SBFont.body(15))
                            .foregroundColor(.sbTextPrimary)
                        Spacer(minLength: 8)
                        Text(LocalizedStringKey(ing.amount))
                            .font(SBFont.caption())
                            .foregroundColor(.sbTextSecondary)
                    }
                    .padding(.vertical, 11)
                    if i < recipe.ingredients.count - 1 { Divider().background(Color.sbBorder) }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.sbSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
        }
        .padding(.bottom, 16)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text("\(i + 1)")
                            .font(SBFont.label(12))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.sbAccent))
                        if i < recipe.steps.count - 1 {
                            Rectangle().fill(Color.sbBorder).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    Text(LocalizedStringKey(step))
                        .font(SBFont.body(15))
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
    }

    /// What's left of today's calories after this dish, in Spartan's words.
    private var fitCard: some View {
        let c = CoachContext.current()
        let left = c.kcalTarget - c.eatenKcal - Int(scaled.calories.rounded())
        let over = left < 0
        return HStack(spacing: 12) {
            CoachAvatar(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(over ? "recipe.fit.over.title" : "recipe.fit.title"))
                    .font(SBFont.heading(14))
                    .foregroundColor(.sbTextPrimary)
                Text(verbatim: String(format: NSLocalizedString(over ? "recipe.fit.over" : "recipe.fit.left", comment: ""),
                                      locale: .current, abs(left)))
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LinearGradient(colors: [Color.sbAccent.opacity(0.18), Color.sbCyan.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbAccent.opacity(0.35)))
    }

    // MARK: Action

    private var servingsLabel: String {
        String(format: servings == servings.rounded() ? "%.0f" : "%.1f", locale: .current, servings)
    }

    /// Portions and logging, always in reach above the tab bar.
    private var actionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                stepButton("minus") { servings = max(0.5, servings - 0.5) }
                VStack(spacing: 0) {
                    Text(verbatim: servingsLabel)
                        .font(SBFont.heading(15))
                        .foregroundColor(.sbTextPrimary)
                    Text(LocalizedStringKey(servings == 1 ? "recipe.portion.one" : "recipe.portion.many"))
                        .font(SBFont.label(9))
                        .foregroundColor(.sbTextSecondary)
                }
                .frame(minWidth: 52)
                stepButton("plus") { servings = min(5, servings + 0.5) }
            }
            .frame(height: 52)
            .background(Color.sbSurface)
            .cornerRadius(15)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.sbBorder))

            Button(action: log) {
                Label("recipe.log", systemImage: "plus")
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
        .padding(.bottom, 10 + bottomInset)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.sbBorder).frame(height: 1), alignment: .top)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.sbTextSecondary)
                .frame(width: 40, height: 52)
                // The whole box takes the tap, not just the thin "−" line.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Logged to the meal that fits the time of day, not always dinner.
    private func log() {
        let hour = Calendar.current.component(.hour, from: Date())
        let meal: MealType = hour < 11 ? .breakfast : hour < 16 ? .lunch : hour < 19 ? .snack : .dinner
        let item = FoodItem(id: recipe.id, name: NSLocalizedString(recipe.name, comment: ""), category: .other,
                            per100g: NutritionInfo(calories: scaled.calories, protein: scaled.protein,
                                                   carbs: scaled.carbs, fat: scaled.fat))
        foodLog.add(item, grams: 100, meal: meal)
        HapticManager.success()
        withAnimation(.spring(response: 0.4)) { loggedMeal = meal }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { loggedMeal = nil }
        }
    }

    private func toast(_ meal: MealType) -> some View {
        let key: String
        switch meal {
        case .breakfast: key = "recipe.logged.breakfast"
        case .lunch:     key = "recipe.logged.lunch"
        case .snack:     key = "recipe.logged.snack"
        case .dinner:    key = "recipe.logged.dinner"
        }
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.sbGreen)
            Text(LocalizedStringKey(key)).font(SBFont.body()).foregroundColor(.sbTextPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
    }
}

// MARK: - Recipe Identifiable for navigationDestination

extension Recipe: Hashable {
    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
