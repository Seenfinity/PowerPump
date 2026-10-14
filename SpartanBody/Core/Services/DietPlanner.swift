import Foundation

/// Builds a week of meals with portions, so each day adds up to that day's
/// target instead of being a list of dish names.
///
/// Targets follow training load (carb cycling): protein and fat stay steady,
/// carbohydrates go up on heavy days and down on rest days, and the week
/// still averages out to the calorie target.
enum DietPlanner {

    struct Week {
        var days: [DayMeals]
        /// Average of the daily targets — what "your target" means this week.
        var average: MacroTarget
    }

    static func week(schedule: [DayPlan], goal: FitnessGoal, weeklyCalories: Int,
                     protein: Int, weightKg: Double, plantBased: Bool, seed: UInt64,
                     floor: Int = 0, banned: Set<String> = []) -> Week {
        let targets = dailyTargets(schedule: schedule, goal: goal,
                                   weeklyCalories: weeklyCalories, protein: protein,
                                   weightKg: weightKg, floor: floor)
        var rng = SplitMix64(seed: seed)
        var used: [String: Int] = [:]          // recipe id → times used this week
        var yesterday: Set<String> = []
        var lastSnack: String?
        var days: [DayMeals] = []

        for (idx, day) in schedule.enumerated() {
            let target = targets[idx]
            var today: Set<String> = []
            var meals: [PlannedMeal] = []

            // Breakfast 25%, lunch 35%, dinner 28%, snack fills the rest.
            let breakfast = plantBased
                ? plantBreakfast(kcal: Double(target.kcal) * 0.25)
                : pickRecipe(from: allowed(breakfastPool(), banned), slot: .breakfast,
                             target: share(target, 0.25), goal: goal,
                             used: used, avoid: yesterday, rng: &rng)
            if let breakfast { meals.append(breakfast); note(breakfast, &used, &today) }

            // Lunch and dinner aim at what's still missing from the day, not a
            // fixed share: after a low-protein lunch, dinner goes looking for
            // protein. Picking each meal blind left some days at 84% protein.
            // Remaining shares: lunch 0.35, dinner 0.28, snack 0.12.
            for (slot, share, left) in [(PlannedMeal.MealSlot.lunch, 0.35, 0.75), (.dinner, 0.28, 0.40)] {
                let slotTarget = remaining(target, after: meals, fraction: share / left)
                if var m = pickRecipe(from: allowed(mainPool(plantBased: plantBased), banned), slot: slot,
                                      target: slotTarget, goal: goal,
                                      used: used, avoid: yesterday.union(today), rng: &rng) {
                    addProteinSide(to: &m, need: slotTarget.protein - Double(m.protein),
                                   plantBased: plantBased, variant: idx)
                    meals.append(m); note(m, &used, &today)
                }
            }

            // The snack closes whatever the three meals left open.
            let gap = Macros(kcal:    Double(target.kcal    - meals.reduce(0) { $0 + $1.kcal }),
                             protein: Double(target.protein - meals.reduce(0) { $0 + $1.protein }),
                             carbs:   Double(target.carbs   - meals.reduce(0) { $0 + $1.carbs }),
                             fat:     Double(target.fat     - meals.reduce(0) { $0 + $1.fat }))
            let snack = self.snack(gap: gap, dayKcal: Double(target.kcal),
                                   plantBased: plantBased, avoid: lastSnack)
            lastSnack = snack.items?.first?.foodID
            // Keep breakfast · lunch · snack · dinner order.
            meals.insert(snack, at: min(2, meals.count))

            days.append(DayMeals(
                day: day.day,
                breakfast: meals.first { $0.slot == .breakfast }?.name ?? "",
                lunch:     meals.first { $0.slot == .lunch }?.name ?? "",
                dinner:    meals.first { $0.slot == .dinner }?.name ?? "",
                meals: meals, intensity: day.intensity ?? (day.isWorkout ? .medium : .rest),
                target: target))
            yesterday = today
        }

        let n = Double(max(targets.count, 1))
        let average = MacroTarget(
            kcal:    Int((Double(targets.reduce(0) { $0 + $1.kcal }) / n).rounded()),
            protein: protein,
            carbs:   Int((Double(targets.reduce(0) { $0 + $1.carbs }) / n).rounded()),
            fat:     targets.first?.fat ?? 0)
        return Week(days: days, average: average)
    }

    // MARK: - Daily targets

    static func dailyTargets(schedule: [DayPlan], goal: FitnessGoal, weeklyCalories: Int,
                             protein: Int, weightKg: Double, floor: Int = 0) -> [MacroTarget] {
        func factor(_ d: DayPlan) -> Double {
            let base: Double
            switch d.intensity ?? (d.isWorkout ? .medium : .rest) {
            case .heavy:  base = 1.08
            case .medium: base = 1.03
            case .light:  base = 1.00
            case .deload: base = 0.97
            case .rest:   base = 0.93
            case .sport:  base = 1.06   // a class or match burns like a hard session
            }
            // Gym *and* practice the same day: fuel both.
            return base + (d.isWorkout && d.isSportDay ? 0.05 : 0)
        }
        let raw = schedule.map(factor)
        let mean = raw.reduce(0, +) / Double(max(raw.count, 1))

        // Fat: the goal's share of the non-protein calories, never below
        // 0.6 g/kg (hormones need it). Constant across the week.
        let fatShare: Double
        switch goal {
        case .loseWeight: fatShare = 0.40
        case .gainMuscle: fatShare = 0.30
        case .stayFit:    fatShare = 0.35
        }
        let nonProtein = Double(max(weeklyCalories - protein * 4, 0))
        let fat = max(Int(nonProtein * fatShare / 9), Int(0.6 * weightKg))

        // The week's average already respects the safety floor, but a rest
        // day 7% under it took a small woman's target to 1115 kcal. Lift
        // those days to the floor and take the difference from the days
        // above it — though never more than half their margin, or a week
        // planned right at the floor flattened every day to it and training
        // days lost their extra fuel. Safety and fuel come before hitting
        // the weekly average to the calorie.
        var dayKcal = raw.map { Double(weeklyCalories) * $0 / mean }
        let minimum = Double(floor)
        let lift = dayKcal.reduce(0) { $0 + max(minimum - $1, 0) }
        if lift > 0 {
            let room = dayKcal.reduce(0) { $0 + max($1 - minimum, 0) }
            let take = min(lift, room / 2)
            dayKcal = dayKcal.map { k in
                k <= minimum ? minimum : k - (k - minimum) / max(room, 1) * take
            }
        }

        return dayKcal.map { kcal in
            let carbs = max(Int((kcal - Double(protein * 4 + fat * 9)) / 4), 50)
            return MacroTarget(kcal: protein * 4 + carbs * 4 + fat * 9,
                               protein: protein, carbs: carbs, fat: fat)
        }
    }

    // MARK: - Recipes

    /// Breakfasts: recipes tagged as such plus egg and dairy dishes that work
    /// in the morning.
    /// A pool without the recipes the user dislikes — unless that would
    /// leave nothing to choose from.
    private static func allowed(_ pool: [Recipe], _ banned: Set<String>) -> [Recipe] {
        let kept = pool.filter { !banned.contains($0.id) }
        return kept.isEmpty ? pool : kept
    }

    /// Another dish for the same slot with similar calories and protein, for
    /// "change my dinner". nil for snacks, which aren't recipes.
    static func alternative(to meal: PlannedMeal, goal: FitnessGoal, plantBased: Bool,
                            banned: Set<String>, seed: UInt64) -> PlannedMeal? {
        guard meal.recipeID != nil else { return nil }
        let pool = meal.slot == .breakfast ? breakfastPool() : mainPool(plantBased: plantBased)
        var avoid = banned
        if let id = meal.recipeID { avoid.insert(id) }
        let candidates = pool.filter { !avoid.contains($0.id) }
        guard !candidates.isEmpty else { return nil }
        var rng = SplitMix64(seed: seed)
        let target = Macros(kcal: Double(meal.kcal), protein: Double(meal.protein),
                            carbs: Double(meal.carbs), fat: Double(meal.fat))
        return pickRecipe(from: candidates, slot: meal.slot, target: target, goal: goal,
                          used: [:], avoid: [], rng: &rng)
    }

    private static func breakfastPool() -> [Recipe] {
        let morning: Set<String> = ["egg_white_omelette", "veggie_omelette",
                                    "spinach_frittata", "cottage_cheese_bowl"]
        return RecipeDatabase.all.filter { $0.tags.contains("Breakfast") || morning.contains($0.id) }
    }

    private static func mainPool(plantBased: Bool) -> [Recipe] {
        let breakfastIDs = Set(breakfastPool().map(\.id))
        return RecipeDatabase.all.filter { r in
            !breakfastIDs.contains(r.id)
                && (!plantBased || r.tags.contains("Vegan") || r.tags.contains("Vegetarian"))
        }
    }

    /// Macros as doubles, for scoring.
    struct Macros {
        var kcal, protein, carbs, fat: Double
    }

    private static func share(_ t: MacroTarget, _ f: Double) -> Macros {
        Macros(kcal: Double(t.kcal) * f, protein: Double(t.protein) * f,
               carbs: Double(t.carbs) * f, fat: Double(t.fat) * f)
    }

    /// `fraction` of what the day still needs once `meals` are eaten.
    private static func remaining(_ t: MacroTarget, after meals: [PlannedMeal], fraction f: Double) -> Macros {
        func left(_ total: Int, _ used: Int) -> Double { max(Double(total - used), 0) * f }
        return Macros(kcal:    left(t.kcal,    meals.reduce(0) { $0 + $1.kcal }),
                      protein: left(t.protein, meals.reduce(0) { $0 + $1.protein }),
                      carbs:   left(t.carbs,   meals.reduce(0) { $0 + $1.carbs }),
                      fat:     left(t.fat,     meals.reduce(0) { $0 + $1.fat }))
    }

    /// How far a portion is from a meal's target, weighting what matters:
    /// calories first, then protein, then carbs, then fat. Relative errors so
    /// a 20 g miss on 40 g of protein counts more than on 150 g of carbs.
    private static func distance(_ n: NutritionInfo, _ t: Macros) -> Double {
        func rel(_ a: Double, _ b: Double) -> Double { abs(a - b) / max(b, 10) }
        return rel(n.calories, t.kcal) * 1.0 + rel(n.protein, t.protein) * 1.0
             + rel(n.carbs, t.carbs) * 0.5 + rel(n.fat, t.fat) * 0.3
    }

    /// Chooses the recipe and portion (0.75–2 servings) closest to the meal's
    /// macro target, avoiding anything eaten today or yesterday and rotating
    /// through the week.
    ///
    /// Scoring on calories alone overshot protein badly — most recipes are
    /// protein-heavy — and left carbs short on heavy days.
    private static func pickRecipe(from pool: [Recipe], slot: PlannedMeal.MealSlot, target: Macros,
                                   goal: FitnessGoal, used: [String: Int], avoid: Set<String>,
                                   rng: inout SplitMix64) -> PlannedMeal? {
        let goalTag: RecipeGoal = goal == .loseWeight ? .weightLoss
            : goal == .gainMuscle ? .muscleGain : .maintenance
        // Shuffle first so equally good options rotate from week to week.
        let scored = pool.shuffled(using: &rng).map { r -> (Recipe, Double, Double) in
            let raw = target.kcal / max(r.nutrition.calories, 1)
            // ½ to 2½ servings: a 1,250 kcal day needs half portions, a
            // 3,200 kcal day more than two.
            let servings = min(max((raw * 4).rounded() / 4, 0.5), 2.5)
            var score = distance(r.nutrition.scaled(by: servings), target)
            if avoid.contains(r.id) { score += 1.5 }
            score += Double(used[r.id] ?? 0) * 0.35
            if r.goal != goalTag    { score += 0.15 }
            return (r, score, servings)
        }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        let (r, _, servings) = best
        let n = r.nutrition.scaled(by: servings)
        return PlannedMeal(slot: slot, name: r.name, recipeID: r.id, servings: servings,
                           items: nil, kcal: Int(n.calories.rounded()),
                           protein: Int(n.protein.rounded()), carbs: Int(n.carbs.rounded()),
                           fat: Int(n.fat.rounded()))
    }

    /// Tops up a lunch or dinner that falls short of protein with a lean
    /// side — seitan, tofu or tempeh for plant-based menus; chicken, turkey or
    /// tuna otherwise — in the grams needed. Most recipes in the library carry
    /// 20–40 g; a 130 kg lifter or a vegan on 160 g a day can't get there from
    /// the dish alone.
    ///
    /// The dish shrinks to make room, so the meal keeps its calories: adding
    /// the side on top pushed small plant-based eaters 30% over their day.
    private static func addProteinSide(to meal: inout PlannedMeal, need: Double,
                                       plantBased: Bool, variant: Int) {
        guard need >= 12 else { return }
        // Seitan for plant menus: twice the protein per calorie of tofu or
        // tempeh, which matters on a tight calorie budget. Tofu only rotates
        // in when the gap is small.
        let sides: [(id: String, maxG: Double)] = plantBased
            ? (need > 20 ? [("seitan", 250)] : [("seitan", 250), ("tofu", 200)])
            : [("chicken_breast", 250), ("turkey_breast", 250), ("tuna_canned", 180)]
        let pick = sides[variant % sides.count]
        guard let food = FoodDatabase.all.first(where: { $0.id == pick.id }),
              food.per100g.protein > 0 else { return }
        let grams = min(max((need / food.per100g.protein * 100 / 10).rounded() * 10, 30), pick.maxG)
        let side = food.nutrition(grams: grams)

        // Rebuild the dish at a smaller portion that leaves room for the side.
        if let id = meal.recipeID, let recipe = RecipeDatabase.all.first(where: { $0.id == id }),
           let servings = meal.servings {
            let perServing = max(recipe.nutrition.calories, 1)
            let fewer = ((Double(meal.kcal) - side.calories) / perServing * 4).rounded() / 4
            let newServings = min(max(fewer, 0.5), servings)
            let dish = recipe.nutrition.scaled(by: newServings)
            meal.servings = newServings
            meal.kcal = Int(dish.calories.rounded())
            meal.protein = Int(dish.protein.rounded())
            meal.carbs = Int(dish.carbs.rounded())
            meal.fat = Int(dish.fat.rounded())
        }
        meal.items = [PlannedFood(foodID: food.id, name: food.name, grams: Int(grams))]
        meal.kcal += Int(side.calories.rounded())
        meal.protein += Int(side.protein.rounded())
        meal.carbs += Int(side.carbs.rounded())
        meal.fat += Int(side.fat.rounded())
    }

    private static func note(_ m: PlannedMeal, _ used: inout [String: Int], _ today: inout Set<String>) {
        guard let id = m.recipeID else { return }
        used[id, default: 0] += 1
        today.insert(id)
    }

    // MARK: - Food combinations

    /// Oats, soy milk, banana and peanut butter — there's no plant-based
    /// breakfast recipe in the library.
    private static func plantBreakfast(kcal: Double) -> PlannedMeal? {
        combo(slot: .breakfast,
              base: [("oats", 60), ("soy_milk", 350), ("banana", 100), ("peanut_butter", 15)],
              kcal: kcal)
    }

    /// The snack that best closes the day's remaining gap. Protein short →
    /// dairy or a shake; carbs short (heavy days) → fruit and rice cakes or
    /// oats; otherwise fruit with nuts. Different from yesterday's when a
    /// comparable option exists.
    private static func snack(gap: Macros, dayKcal: Double, plantBased: Bool, avoid: String?) -> PlannedMeal {
        // Up to a quarter of the day: big eaters need a real fourth meal.
        let kcal = min(max(gap.kcal, 100), max(650, dayKcal * 0.25))
        var options: [[(String, Double)]] = [
            [("apple", 150), ("peanut_butter", 20)],
            [("rice_cakes", 30), ("peanut_butter", 15), ("banana", 100)],
            [("banana", 120), ("almonds", 20)],
            [("oats", 50), ("soy_milk", 250), ("banana", 100)],
        ]
        if plantBased {
            // Plant snacks that actually carry protein.
            options += [
                [("edamame", 200), ("rice_cakes", 20)],
                [("seitan", 100), ("rice_cakes", 30), ("banana", 100)],
                [("tofu", 200), ("rice_cakes", 30)],
                // A pea-protein shake: the plant equivalent of whey, and
                // the only way a small vegan on a deficit reaches her protein.
                [("pea_protein", 30), ("soy_milk", 250)],
                [("pea_protein", 30), ("banana", 100)],
            ]
        } else {
            options += [
                [("greek_yogurt", 250), ("blueberries", 100), ("almonds", 15)],
                [("cottage_cheese", 200), ("strawberries", 150)],
                [("whey_protein", 30), ("banana", 120), ("milk_skim", 250)],
                [("greek_yogurt", 200), ("oats", 40), ("banana", 100)],
            ]
        }
        let target = Macros(kcal: kcal, protein: max(gap.protein, 5),
                            carbs: max(gap.carbs, 10), fat: max(gap.fat, 3))
        let built = options.compactMap { combo(slot: .snack, base: $0, kcal: kcal) }
        let best = built.min { a, b in
            func score(_ m: PlannedMeal) -> Double {
                // The snack is the last chance to fix protein for the day, so a
                // protein miss here counts extra.
                let proteinMiss = abs(Double(m.protein) - target.protein) / max(target.protein, 10)
                return distance(NutritionInfo(calories: Double(m.kcal), protein: Double(m.protein),
                                              carbs: Double(m.carbs), fat: Double(m.fat)), target)
                    + proteinMiss * 0.6
                    + (m.items?.first?.foodID == avoid ? 0.25 : 0)
            }
            return score(a) < score(b)
        }
        return best ?? PlannedMeal(slot: .snack, name: "Apple", recipeID: nil, servings: nil,
                                   items: nil, kcal: 0, protein: 0, carbs: 0, fat: 0)
    }

    /// Scales a set of foods together to hit `kcal`, rounding to 5 g.
    private static func combo(slot: PlannedMeal.MealSlot,
                              base: [(String, Double)], kcal: Double) -> PlannedMeal? {
        let foods = base.compactMap { id, g in FoodDatabase.all.first { $0.id == id }.map { ($0, g) } }
        guard foods.count == base.count else { return nil }
        let baseKcal = foods.reduce(0) { $0 + $1.0.nutrition(grams: $1.1).calories }
        let scale = min(max(kcal / max(baseKcal, 1), 0.5), 2.5)

        var items: [PlannedFood] = []
        var total = NutritionInfo(calories: 0, protein: 0, carbs: 0, fat: 0)
        for (food, g) in foods {
            // No 400 g apples: a single food never goes past 2× its base.
            let grams = max(5, (min(g * scale, g * 2.5) / 5).rounded() * 5)
            let n = food.nutrition(grams: grams)
            total = NutritionInfo(calories: total.calories + n.calories,
                                  protein: total.protein + n.protein,
                                  carbs: total.carbs + n.carbs,
                                  fat: total.fat + n.fat)
            items.append(PlannedFood(foodID: food.id, name: food.name, grams: Int(grams)))
        }
        return PlannedMeal(slot: slot, name: foods[0].0.name, recipeID: nil, servings: nil, items: items,
                           kcal: Int(total.calories.rounded()), protein: Int(total.protein.rounded()),
                           carbs: Int(total.carbs.rounded()), fat: Int(total.fat.rounded()))
    }
}

/// Small deterministic generator: the same seed always gives the same week,
/// so a plan can be reproduced, while a new seed each week rotates the menu.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
