import Foundation

// Generates a personalised fitness plan locally — no API key, no internet needed.
struct LocalCoachService {

    /// Builds the week from what the user actually did.
    ///
    /// CoachAnalyzer reads the last weeks and decides volume, deload and
    /// calories; WeeklyPlanner lays out heavy/medium/light days with loads;
    /// DietPlanner turns each day's target into meals with portions. This
    /// file adds the words around it: analysis, tips, injury substitutions.
    static func generatePlan(_ i: CoachInputs) -> FitnessPlan {
        let decision = CoachAnalyzer.analyze(i)
        let ctx = (i.extraContext + " " + i.memoryNotes).lowercased()
        let plantBased = hasVeganKeyword(ctx)

        // Training: plain lines first, then injury/home swaps, then loads —
        // so a swapped exercise never carries the original lift's kilos.
        let week = WeeklyPlanner.week(i, decision, dayNames: days)
        var schedule = week.days
        if !ctx.trimmingCharacters(in: .whitespaces).isEmpty {
            schedule = applyContext(schedule, context: ctx)
        }
        schedule = WeeklyPlanner.annotate(schedule, with: week.loads)

        let diet = DietPlanner.week(schedule: schedule, goal: i.goal,
                                    weeklyCalories: decision.weeklyCalories, protein: i.protein,
                                    weightKg: i.weightKg, plantBased: plantBased, seed: i.seed,
                                    floor: i.sex == .female ? 1200 : 1500, banned: i.bannedRecipes)

        // Words: the older adaptive sentences still fit, fed with real data now.
        let rate = CoachAnalyzer.weightRate(i.weighIns, now: i.now)
        let history = AdaptiveContext(
            pastWorkouts: i.sessions.count,
            workoutsLast7Days: decision.report.sessionsDone,
            currentStreak: i.currentStreak,
            longestStreak: i.currentStreak,
            avgCaloriesLast7Days: decision.report.avgCalories ?? 0,
            calorieTarget: decision.weeklyCalories,
            weightTrendKg: rate.map { $0 * 2 },       // ≈ change over two weeks
            hasLoggedWeight: !i.weighIns.isEmpty)

        var text = [adaptiveAnalysis(history: history, goal: i.goal),
                    analysis(goal: i.goal, bmi: i.bmi, bmiCategory: i.bmiCategory,
                             weightKg: i.weightKg,
                             // Maintenance = the profile target minus the goal's
                             // built-in deficit/surplus; planned = this week's
                             // calories after the coach's adjustments.
                             maintenance: i.baseCalories - i.goal.dailyCalorieAdjustment,
                             planned: decision.weeklyCalories,
                             activityLevel: i.activityLevel,
                             extraContext: i.extraContext + " " + i.memoryNotes)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var tips = adaptiveTips(history: history, goal: i.goal, plantBased: plantBased)

        if let sportID = i.sportID, i.sportDaysPerWeek > 0 {
            let family = SportFamily.forSport(id: sportID)
            let sportName = NSLocalizedString(SportLibrary.byID(sportID)?.nameKey ?? sportID, comment: "")
            var sentence = String(format: sportAnalysisFormat(family), sportName, i.sportDaysPerWeek)
            if i.sportDaysPerWeek == 1 {
                // The templates are written for "N days"; one day read "1 días".
                for (plural, singular) in [(" 1 días", " 1 día"), (" 1 days", " 1 day"), (" 1 jours", " 1 jour"),
                                           (" 1 giorni", " 1 giorno"), (" 1 dias", " 1 dia")] {
                    sentence = sentence.replacingOccurrences(of: plural, with: singular)
                }
            }
            text += " " + sentence
            tips = Array((sportTips(family) + tips).prefix(max(tips.count, 4)))
        }

        // Foods the user told Spartan they don't eat leave the plan's words too.
        text = dropping(i.dislikedFoods, from: text)
        tips = tips.map { dropping(i.dislikedFoods, from: $0) }

        let avg = diet.average
        return FitnessPlan(
            analysis:       text,
            weeklySchedule: schedule,
            nutritionPlan:  AINutritionPlan(
                calories: avg.kcal, protein: avg.protein, carbs: avg.carbs, fat: avg.fat,
                tips: [NSLocalizedString("coach.tip.carbCycling", comment: "")]
                    + nutritionTips(goal: i.goal).map { dropping(i.dislikedFoods, from: $0) }),
            tips:           tips,
            motivation:     motivation(goal: i.goal),
            weeklyMeals:    diet.days,
            report:         decision.report)
    }

    /// Takes foods out of the lists inside a sentence:
    /// "(legumbres, tofu, tempeh)" → "(legumbres, tempeh)".
    static func dropping(_ foods: [String], from text: String) -> String {
        var out = text
        for food in foods where food.count >= 3 {
            let f = NSRegularExpression.escapedPattern(for: food)
            for pattern in [",\\s*\\b\(f)\\b", "\\b\(f)\\b,\\s*"] {
                out = out.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            }
        }
        return out
    }

    static func sportAnalysisFormat(_ family: SportFamily) -> String {
        switch family {
        case .grappling:
            switch lang {
            case "es": return "Como entrenas %@ %d días por semana, tu plan de gym prioriza agarre, cuello y core, y mantiene el volumen de pierna moderado para que llegues fresco al tatami."
            case "fr": return "Comme tu pratiques %@ %d jours par semaine, ton plan muscu mise sur la poigne, le cou et le gainage, avec un volume jambes modéré pour rester frais à l'entraînement."
            case "it": return "Dato che pratichi %@ %d giorni a settimana, il piano palestra punta su presa, collo e core, con un volume gambe moderato per arrivare fresco sul tatami."
            case "pt-BR": return "Como você treina %@ %d dias por semana, seu plano de academia prioriza pegada, pescoço e core, mantendo o volume de pernas moderado para chegar descansado no tatame."
            default: return "Since you train %@ %d days a week, your gym plan prioritises grip, neck and core work, and keeps leg volume moderate so you arrive fresh to practice."
            }
        case .endurance:
            switch lang {
            case "es": return "Como practicas %@ %d días por semana, el plan refuerza piernas y core con volumen controlado para no robarle energía a tus salidas."
            case "fr": return "Comme tu pratiques %@ %d jours par semaine, le plan renforce jambes et gainage avec un volume contrôlé pour ne pas voler d'énergie à tes sorties."
            case "it": return "Visto che pratichi %@ %d giorni a settimana, il piano rinforza gambe e core con volume controllato per non togliere energia alle tue uscite."
            case "pt-BR": return "Como você pratica %@ %d dias por semana, o plano fortalece pernas e core com volume controlado para não roubar energia dos seus treinos."
            default: return "Since you do %@ %d days a week, the plan strengthens legs and core with controlled volume so it never steals energy from your sessions."
            }
        case .racquet:
            switch lang {
            case "es": return "Como juegas %@ %d días por semana, el plan añade potencia rotacional y hombros fuertes, cuidando codos y muñecas."
            case "fr": return "Comme tu joues au %@ %d jours par semaine, le plan ajoute de la puissance rotationnelle et des épaules solides, en protégeant coudes et poignets."
            case "it": return "Dato che giochi a %@ %d giorni a settimana, il piano aggiunge potenza rotazionale e spalle forti, proteggendo gomiti e polsi."
            case "pt-BR": return "Como você joga %@ %d dias por semana, o plano adiciona potência rotacional e ombros fortes, protegendo cotovelos e punhos."
            default: return "Since you play %@ %d days a week, the plan adds rotational power and strong shoulders while protecting elbows and wrists."
            }
        case .team:
            switch lang {
            case "es": return "Como juegas %@ %d días por semana, el plan trabaja sprint, agilidad y fuerza de pierna, con recuperación pensada para los días de partido."
            case "fr": return "Comme tu joues au %@ %d jours par semaine, le plan travaille sprint, agilité et force des jambes, avec une récupération pensée pour les jours de match."
            case "it": return "Visto che giochi a %@ %d giorni a settimana, il piano lavora su sprint, agilità e forza delle gambe, con recupero pensato per i giorni di partita."
            case "pt-BR": return "Como você joga %@ %d dias por semana, o plano trabalha sprint, agilidade e força de pernas, com recuperação pensada para os dias de jogo."
            default: return "Since you play %@ %d days a week, the plan trains sprints, agility and leg strength, with recovery planned around game days."
            }
        case .water:
            switch lang {
            case "es": return "Como practicas %@ %d días por semana, el plan refuerza hombros, espalda y core, la base de una buena brazada."
            case "fr": return "Comme tu pratiques %@ %d jours par semaine, le plan renforce épaules, dos et gainage, la base d'un bon mouvement dans l'eau."
            case "it": return "Dato che pratichi %@ %d giorni a settimana, il piano rinforza spalle, schiena e core, la base di una buona bracciata."
            case "pt-BR": return "Como você pratica %@ %d dias por semana, o plano fortalece ombros, costas e core, a base de uma boa braçada."
            default: return "Since you do %@ %d days a week, the plan strengthens shoulders, back and core, the base of every good stroke."
            }
        case .mindBody:
            switch lang {
            case "es": return "Como practicas %@ %d días por semana, ya cubres movilidad y control, así que el gym se centra en fuerza que lo complementa."
            case "fr": return "Comme tu pratiques %@ %d jours par semaine, la mobilité est déjà couverte, donc la muscu se concentre sur la force complémentaire."
            case "it": return "Visto che pratichi %@ %d giorni a settimana, la mobilità è già coperta, quindi la palestra si concentra sulla forza complementare."
            case "pt-BR": return "Como você pratica %@ %d dias por semana, a mobilidade já está coberta, então a academia foca na força complementar."
            default: return "Since you practice %@ %d days a week, mobility is covered, so the gym focuses on complementary strength."
            }
        case .power:
            switch lang {
            case "es": return "Como practicas %@ %d días por semana, el plan equilibra fuerza general con la energía que tu deporte ya exige."
            case "fr": return "Comme tu pratiques %@ %d jours par semaine, le plan équilibre force générale et énergie que ton sport exige déjà."
            case "it": return "Dato che pratichi %@ %d giorni a settimana, il piano bilancia forza generale ed energia che il tuo sport già richiede."
            case "pt-BR": return "Como você pratica %@ %d dias por semana, o plano equilibra força geral com a energia que seu esporte já exige."
            default: return "Since you practice %@ %d days a week, the plan balances general strength with the energy your sport already demands."
            }
        }
    }

    static func supportFocusFormat() -> String {
        switch lang {
        case "es": return "Fuerza para %@"
        case "fr": return "Force pour %@"
        case "it": return "Forza per %@"
        case "pt-BR": return "Força para %@"
        default: return "Strength for %@"
        }
    }

    static func supportExercises(_ family: SportFamily) -> [String] {
        switch family {
        case .grappling:
            return ["Dead Hang 4×30 sec", "Farmer Carry 4×40 m", "Towel Pull-ups 3×6",
                    "Neck Bridge 3×10", "Hip Escape Drill 3×10", "Plank 3×60 sec"]
        case .endurance:
            return ["Squat 4×8", "Romanian Deadlift 3×10", "Walking Lunge 3×12",
                    "Calf Raise 4×15", "Plank 3×60 sec", "Glute Bridge 3×15"]
        case .racquet:
            return ["Cable Rotation 3×12 each side", "Lateral Raise 3×15", "Face Pull 3×15",
                    "Medicine Ball Slam 3×10", "Wrist Curl 3×15", "Plank 3×45 sec"]
        case .team:
            return ["Box Jump 4×8", "Sprint 6×30 m", "Goblet Squat 3×12",
                    "Nordic Curl 3×6", "Lateral Bound 3×8 each side", "Plank 3×45 sec"]
        case .water:
            return ["Pull-ups 4×8", "Overhead Press 3×10", "Face Pull 3×15",
                    "Lat Pulldown 3×12", "Russian Twist 3×20", "Superman Hold 3×30 sec"]
        case .mindBody:
            return ["Squat 3×10", "Push-ups 3×12", "Dumbbell Row 3×12",
                    "Hip Thrust 3×12", "Overhead Press 3×10", "Dead Hang 3×20 sec"]
        case .power:
            return ["Deadlift 4×5", "Pull-ups 4×8", "Overhead Press 3×8",
                    "Farmer Carry 3×40 m", "Box Jump 3×8", "Plank 3×60 sec"]
        }
    }

    static func sportTips(_ family: SportFamily) -> [String] {
        switch family {
        case .grappling:
            switch lang {
            case "es": return ["Entrena agarre 2 veces por semana: colgarte de la barra y cargar peso pesado se transfiere directo al tatami.",
                               "En semanas con mucho sparring, baja una serie a cada ejercicio de pierna. Recuperar vale más que sumar volumen."]
            case "fr": return ["Travaille ta poigne 2 fois par semaine : suspensions et portés lourds se transfèrent directement sur le tapis.",
                               "Les semaines chargées en sparring, enlève une série aux exercices de jambes. Récupérer vaut mieux qu'accumuler."]
            case "it": return ["Allena la presa 2 volte a settimana: sospensioni alla sbarra e trasporti pesanti si trasferiscono subito sul tatami.",
                               "Nelle settimane con tanto sparring, togli una serie agli esercizi per le gambe. Recuperare vale più che accumulare volume."]
            case "pt-BR": return ["Treine a pegada 2 vezes por semana: ficar pendurado na barra e carregar peso transferem direto para o tatame.",
                                  "Em semanas de muito sparring, tire uma série dos exercícios de perna. Recuperar vale mais que acumular volume."]
            default: return ["Train grip twice a week: dead hangs and heavy carries transfer straight to the mat.",
                             "On heavy sparring weeks, drop one set from every leg exercise. Recovery beats extra volume."]
            }
        case .endurance:
            switch lang {
            case "es": return ["Haz la fuerza de pierna al menos 6 horas antes o después de tu sesión larga para no llegar fatigado.",
                               "La fuerza de core mejora tu postura cuando llega el cansancio: no te saltes las planchas."]
            case "fr": return ["Fais le renfo jambes au moins 6 heures avant ou après ta sortie longue pour éviter la fatigue croisée.",
                               "Le gainage améliore ta posture quand la fatigue arrive : ne saute pas les planches."]
            case "it": return ["Fai la forza gambe almeno 6 ore prima o dopo la sessione lunga per evitare fatica incrociata.",
                               "Il core migliora la postura quando arriva la stanchezza: non saltare i plank."]
            case "pt-BR": return ["Faça o treino de pernas pelo menos 6 horas antes ou depois da sessão longa para evitar fadiga cruzada.",
                                  "O core melhora sua postura quando o cansaço chega: não pule as pranchas."]
            default: return ["Schedule leg strength at least 6 hours away from your long session to avoid stacking fatigue.",
                             "Core strength holds your form together when fatigue hits: don't skip the planks."]
            }
        case .racquet:
            switch lang {
            case "es": return ["La potencia de tus golpes nace en las caderas: los giros con cable y los lanzamientos de balón son tu mejor inversión.",
                               "Refuerza el manguito rotador con face pulls: es el seguro de vida de tu hombro."]
            case "fr": return ["La puissance de tes frappes vient des hanches : rotations au câble et lancers de medecine-ball sont ton meilleur investissement.",
                               "Renforce ta coiffe des rotateurs avec des face pulls : c'est l'assurance-vie de ton épaule."]
            case "it": return ["La potenza dei tuoi colpi nasce dalle anche: rotazioni al cavo e lanci della palla medica sono il miglior investimento.",
                               "Rinforza la cuffia dei rotatori con i face pull: è l'assicurazione sulla vita della tua spalla."]
            case "pt-BR": return ["A potência dos seus golpes nasce no quadril: rotações no cabo e arremessos de medicine ball são o melhor investimento.",
                                  "Fortaleça o manguito rotador com face pulls: é o seguro de vida do seu ombro."]
            default: return ["Your shot power comes from the hips: cable rotations and med-ball throws are your best investment.",
                             "Strengthen the rotator cuff with face pulls: it's your shoulder's life insurance."]
            }
        case .team:
            switch lang {
            case "es": return ["Los isquios fuertes previenen la lesión más común del deporte de equipo: no te saltes los curl nórdicos.",
                               "Programa la pierna pesada lejos de los partidos: 48 horas de margen como mínimo."]
            case "fr": return ["Des ischios forts préviennent la blessure la plus courante des sports co : ne saute pas les nordic curls.",
                               "Programme les jambes lourdes loin des matchs : 48 heures de marge minimum."]
            case "it": return ["Femorali forti prevengono l'infortunio più comune negli sport di squadra: non saltare i nordic curl.",
                               "Programma il lavoro pesante sulle gambe lontano dalle partite: almeno 48 ore di margine."]
            case "pt-BR": return ["Posteriores fortes previnem a lesão mais comum do esporte coletivo: não pule o nordic curl.",
                                  "Programe o treino pesado de pernas longe dos jogos: 48 horas de folga no mínimo."]
            default: return ["Strong hamstrings prevent the most common team-sport injury: don't skip nordic curls.",
                             "Schedule heavy leg work away from games: 48 hours of buffer minimum."]
            }
        case .water:
            switch lang {
            case "es": return ["Equilibra tanta brazada con trabajo de espalda: por cada empuje, un jalón.",
                               "Los hombros del nadador necesitan face pulls y rotaciones externas cada semana."]
            case "fr": return ["Équilibre le volume de nage avec du travail de dos : pour chaque poussée, un tirage.",
                               "Les épaules du nageur ont besoin de face pulls et de rotations externes chaque semaine."]
            case "it": return ["Bilancia tutte quelle bracciate con lavoro di schiena: per ogni spinta, una trazione.",
                               "Le spalle del nuotatore hanno bisogno di face pull e rotazioni esterne ogni settimana."]
            case "pt-BR": return ["Equilibre tanta braçada com trabalho de costas: para cada empurrada, uma puxada.",
                                  "Ombros de nadador precisam de face pulls e rotações externas toda semana."]
            default: return ["Balance all that stroke volume with back work: for every push, a pull.",
                             "Swimmer's shoulders need face pulls and external rotations every week."]
            }
        case .mindBody:
            switch lang {
            case "es": return ["Tu práctica ya te da movilidad: el gym es el lugar para cargar peso y proteger tus huesos a largo plazo.",
                               "Progresa despacio en los básicos: sentadilla, empuje y jalón son el complemento perfecto."]
            case "fr": return ["Ta pratique t'apporte déjà la mobilité : la muscu est là pour charger et protéger tes os sur le long terme.",
                               "Progresse doucement sur les bases : squat, poussée et tirage sont le complément parfait."]
            case "it": return ["La tua pratica ti dà già mobilità: la palestra serve a caricare peso e proteggere le ossa a lungo termine.",
                               "Progredisci con calma sui fondamentali: squat, spinta e trazione sono il complemento perfetto."]
            case "pt-BR": return ["Sua prática já te dá mobilidade: a academia é o lugar de carregar peso e proteger seus ossos a longo prazo.",
                                  "Progrida devagar nos básicos: agachamento, empurrar e puxar são o complemento perfeito."]
            default: return ["Your practice already covers mobility: the gym is where you load weight and protect your bones long term.",
                             "Progress slowly on the basics: squat, push and pull are the perfect complement."]
            }
        case .power:
            switch lang {
            case "es": return ["Tu deporte ya es intenso: en el gym busca calidad sobre cantidad, con básicos pesados y series cortas.",
                               "Duerme 7-9 horas: es donde tu cuerpo convierte el entrenamiento en progreso."]
            case "fr": return ["Ton sport est déjà intense : à la salle, vise la qualité, des mouvements de base lourds et des séries courtes.",
                               "Dors 7 à 9 heures : c'est là que ton corps transforme l'entraînement en progrès."]
            case "it": return ["Il tuo sport è già intenso: in palestra punta alla qualità, fondamentali pesanti e serie brevi.",
                               "Dormi 7-9 ore: è lì che il corpo trasforma l'allenamento in progresso."]
            case "pt-BR": return ["Seu esporte já é intenso: na academia busque qualidade, básicos pesados e séries curtas.",
                                  "Durma de 7 a 9 horas: é quando seu corpo converte treino em progresso."]
            default: return ["Your sport is already intense: in the gym chase quality over quantity, heavy basics and short sets.",
                             "Sleep 7 to 9 hours: that's where your body turns training into progress."]
            }
        }
    }

    // Snapshot of the user's recent activity, passed in so this service stays
    // free of MainActor isolation issues. The caller (AICoachView) collects it.
    struct AdaptiveContext {
        var pastWorkouts: Int            // total completed workouts ever
        var workoutsLast7Days: Int
        var currentStreak: Int
        var longestStreak: Int
        var avgCaloriesLast7Days: Int    // 0 if not enough data
        var calorieTarget: Int
        var weightTrendKg: Double?       // negative = losing, positive = gaining, nil = unknown
        var hasLoggedWeight: Bool

        static let empty = AdaptiveContext(
            pastWorkouts: 0, workoutsLast7Days: 0,
            currentStreak: 0, longestStreak: 0,
            avgCaloriesLast7Days: 0, calorieTarget: 2000,
            weightTrendKg: nil, hasLoggedWeight: false)
    }

    // MARK: - Language helper

    static var lang: String { LanguageManager.shared.selectedCode }

    // MARK: - Adaptive layer (uses real user data)

    // Builds a sentence that opens the analysis when we have meaningful user
    // history. Picks the most positive truth available so the user feels seen.
    private static func adaptiveAnalysis(history: AdaptiveContext, goal: FitnessGoal) -> String {
        if history.currentStreak >= 7 {
            return String(format: NSLocalizedString("coach.adaptive.streak", comment: ""),
                          history.currentStreak)
        }
        if history.pastWorkouts >= 25 {
            return String(format: NSLocalizedString("coach.adaptive.veteran", comment: ""),
                          history.pastWorkouts)
        }
        if history.workoutsLast7Days >= 4 {
            return String(format: NSLocalizedString("coach.adaptive.consistent", comment: ""),
                          history.workoutsLast7Days)
        }
        if let trend = history.weightTrendKg, goal == .loseWeight, trend < -0.3 {
            return String(format: NSLocalizedString("coach.adaptive.lostWeight", comment: ""),
                          abs(trend))
        }
        if let trend = history.weightTrendKg, goal == .gainMuscle, trend > 0.3 {
            return String(format: NSLocalizedString("coach.adaptive.gainedWeight", comment: ""),
                          trend)
        }
        if history.pastWorkouts == 0 {
            return NSLocalizedString("coach.adaptive.beginner", comment: "")
        }
        if history.workoutsLast7Days == 0 && history.pastWorkouts > 0 {
            return NSLocalizedString("coach.adaptive.comeback", comment: "")
        }
        return ""
    }

    // Replaces some of the generic tips with personalized advice when the user
    // already has a history. The total tip count stays the same.
    private static func adaptiveTips(history: AdaptiveContext, goal: FitnessGoal,
                                     plantBased: Bool = false) -> [String] {
        var baseTips = tips(goal: goal).shuffled()

        // Vegan/vegetarian users shouldn't be told to drink casein or whey.
        // Swap any dairy/animal-protein tip for a plant-based one.
        if plantBased {
            let veganTip = NSLocalizedString("coach.tip.veganProtein", comment: "")
            let nonVeganMarkers = ["casein", "caseína", "caseina",
                                   "whey", "lácteo", "lacteo", "dairy",
                                   "latticini", "laticínio", "laitier"]
            baseTips = baseTips.map { tip in
                let low = tip.lowercased()
                return nonVeganMarkers.contains(where: { low.contains($0) }) ? veganTip : tip
            }
            // Guarantee the plant-protein tip appears even if no dairy tip was picked.
            if !baseTips.contains(veganTip) && !baseTips.isEmpty {
                baseTips[baseTips.count - 1] = veganTip
            }
        }

        var injected: [String] = []

        if history.currentStreak >= 14 {
            injected.append(NSLocalizedString("coach.tip.recovery", comment: ""))
        }
        if history.workoutsLast7Days == 0 && history.pastWorkouts > 5 {
            injected.append(NSLocalizedString("coach.tip.restart", comment: ""))
        }
        if history.avgCaloriesLast7Days > 0,
           history.calorieTarget > 0,
           history.avgCaloriesLast7Days < Int(Double(history.calorieTarget) * 0.7) {
            injected.append(NSLocalizedString("coach.tip.eatMore", comment: ""))
        }
        if let trend = history.weightTrendKg, abs(trend) < 0.2, history.hasLoggedWeight {
            injected.append(NSLocalizedString("coach.tip.plateau", comment: ""))
        }

        // Replace the first N tips with personalized ones (preserve order).
        for (i, tip) in injected.enumerated() where i < baseTips.count {
            baseTips[i] = tip
        }
        return baseTips
    }

    // MARK: - Analysis

    private static func analysis(goal: FitnessGoal, bmi: Double, bmiCategory: String,
                                 weightKg: Double, maintenance: Int, planned: Int,
                                 activityLevel: ActivityLevel,
                                 extraContext: String) -> String {
        let base: String
        switch goal {
        case .loseWeight:
            let fmt = NSLocalizedString("coach.analysis.loseWeight", comment: "")
            // The category arrives as its English key ("Overweight"); localize it
            // so it doesn't sit in English inside a translated sentence.
            base = String(format: fmt, bmi, NSLocalizedString(bmiCategory, comment: ""))
        case .gainMuscle:
            let fmt = NSLocalizedString("coach.analysis.gainMuscle", comment: "")
            base = String(format: fmt, Int(weightKg))
        case .stayFit:
            base = NSLocalizedString("coach.analysis.stayFit", comment: "")
        }
        let metabolic    = metabolicInsight(goal: goal, maintenance: maintenance,
                                            planned: planned)
        let suffix       = activitySuffix(activityLevel)
        let contextNote  = contextAnalysisNote(extraContext.lowercased())
        return [base, metabolic, suffix, contextNote]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Maintenance calories and the gap this week's plan opens from them.
    ///
    /// Both come from the same numbers the rest of the app uses. This used to
    /// estimate maintenance as 22 × weight and always quote a 500 kcal
    /// deficit, so the text disagreed with the dashboard and ignored the
    /// coach's weekly calorie changes.
    private static func metabolicInsight(goal: FitnessGoal, maintenance: Int, planned: Int) -> String {
        let delta = planned - maintenance
        let action: String
        if delta <= -50 {
            action = String(format: deficitFormat(), -delta)
        } else if delta >= 50 {
            action = String(format: surplusFormat(), delta)
        } else {
            action = maintenanceMessage()
        }
        return String(format: tdeeFormat(), maintenance) + " " + action
    }

    private static func tdeeFormat() -> String {
        switch lang {
        case "es":    return "Tu gasto calórico diario estimado es %d kcal."
        case "it":    return "Il tuo dispendio calorico giornaliero stimato è %d kcal."
        case "pt-BR": return "Seu gasto calórico diário estimado é %d kcal."
        case "fr":    return "Ta dépense calorique quotidienne estimée est de %d kcal."
        default:      return "Your estimated daily calorie expenditure is %d kcal."
        }
    }

    private static func deficitFormat() -> String {
        switch lang {
        case "es":    return "Tu plan crea un déficit moderado de %d kcal/día, suficiente para perder grasa sin sacrificar músculo."
        case "it":    return "Il tuo piano crea un deficit moderato di %d kcal/giorno, sufficiente per perdere grasso senza sacrificare muscolo."
        case "pt-BR": return "Seu plano cria um déficit moderado de %d kcal/dia, suficiente para perder gordura sem sacrificar músculo."
        case "fr":    return "Ton plan crée un déficit modéré de %d kcal/jour, suffisant pour perdre du gras sans sacrifier le muscle."
        default:      return "Your plan creates a moderate %d kcal/day deficit, enough to lose fat without sacrificing muscle."
        }
    }

    private static func surplusFormat() -> String {
        switch lang {
        case "es":    return "Tu plan añade un superávit de %d kcal/día, ideal para ganar músculo magro minimizando la grasa."
        case "it":    return "Il tuo piano aggiunge un surplus di %d kcal/giorno, ideale per costruire muscolo magro minimizzando il grasso."
        case "pt-BR": return "Seu plano adiciona um superávit de %d kcal/dia, ideal para ganhar músculo magro minimizando gordura."
        case "fr":    return "Ton plan ajoute un surplus de %d kcal/jour, idéal pour construire du muscle maigre en minimisant le gras."
        default:      return "Your plan adds a %d kcal/day surplus, ideal for building lean muscle while minimizing fat gain."
        }
    }

    private static func maintenanceMessage() -> String {
        switch lang {
        case "es":    return "Tu plan equilibra calorías y movimiento para mantener tu composición corporal actual."
        case "it":    return "Il tuo piano bilancia calorie e movimento per mantenere la tua composizione corporea attuale."
        case "pt-BR": return "Seu plano equilibra calorias e movimento para manter sua composição corporal atual."
        case "fr":    return "Ton plan équilibre calories et mouvement pour maintenir ta composition corporelle actuelle."
        default:      return "Your plan balances calories and movement to maintain your current body composition."
        }
    }

    private static func activitySuffix(_ level: ActivityLevel) -> String {
        switch (level, lang) {
        case (.sedentary, "es"): return "Este plan está adaptado para comenzar desde cero con ejercicios seguros y progresivos."
        case (.light,     "es"): return "El plan incluye una progresión gradual adaptada a tu nivel de actividad."
        case (.active,    "es"): return "Dado tu nivel activo, el plan es de alta intensidad con mayor volumen."
        case (.sedentary, "it"): return "Questo piano è pensato per iniziare da zero con esercizi sicuri e progressivi."
        case (.light,     "it"): return "Il piano include una progressione graduale adatta al tuo livello di attività."
        case (.active,    "it"): return "Data la tua elevata attività, il piano è ad alta intensità con maggiore volume."
        case (.sedentary, "pt-BR"): return "Este plano foi adaptado para começar do zero com exercícios seguros e progressivos."
        case (.light,     "pt-BR"): return "O plano inclui uma progressão gradual adaptada ao seu nível de atividade."
        case (.active,    "pt-BR"): return "Dado seu alto nível de atividade, o plano é de alta intensidade com maior volume."
        case (.sedentary, "fr"): return "Ce plan est adapté pour commencer de zéro avec des exercices sûrs et progressifs."
        case (.light,     "fr"): return "Le plan inclut une progression graduelle adaptée à ton niveau d'activité."
        case (.active,    "fr"): return "Vu ton niveau actif, le plan est haute intensité avec plus de volume."
        case (.sedentary, _): return "This plan is designed to start from scratch with safe, progressive exercises."
        case (.light,     _): return "The plan includes gradual progression adapted to your activity level."
        case (.active,    _): return "Given your active lifestyle, this plan is high intensity with greater volume."
        default: return ""
        }
    }

    private static func contextAnalysisNote(_ ctx: String) -> String {
        var notes: [String] = []
        if hasKneeKeyword(ctx)     { notes.append(kneeNote()) }
        if hasShoulderKeyword(ctx) { notes.append(shoulderNote()) }
        if hasWristKeyword(ctx)    { notes.append(wristNote()) }
        if hasBackKeyword(ctx)     { notes.append(backNote()) }
        if hasHomeKeyword(ctx)     { notes.append(homeNote()) }
        if hasNoTimeKeyword(ctx)   { notes.append(noTimeNote()) }
        if hasSittingKeyword(ctx)  { notes.append(sittingNote()) }
        if hasBeginnerKeyword(ctx) { notes.append(beginnerNote()) }
        if hasVeganKeyword(ctx)    { notes.append(veganNote()) }
        return notes.joined(separator: " ")
    }

    private static func kneeNote() -> String {
        switch lang {
        case "es":    return "Se han sustituido ejercicios de alto impacto para proteger tus rodillas."
        case "it":    return "Gli esercizi ad alto impatto sono stati sostituiti per proteggere le ginocchia."
        case "pt-BR": return "Exercícios de alto impacto foram substituídos para proteger seus joelhos."
        case "fr":    return "Les exercices à fort impact ont été remplacés pour protéger tes genoux."
        default:      return "High-impact exercises have been replaced to protect your knees."
        }
    }

    private static func homeNote() -> String {
        switch lang {
        case "es":    return "El plan usa ejercicios con peso corporal y mancuernas para hacerlo desde casa."
        case "it":    return "Il piano usa esercizi a corpo libero e manubri per allenarsi a casa."
        case "pt-BR": return "O plano usa exercícios com peso corporal e halteres para treinar em casa."
        case "fr":    return "Le plan utilise des exercices au poids du corps et haltères pour s'entraîner à la maison."
        default:      return "The plan uses bodyweight and dumbbell exercises for home training."
        }
    }

    private static func backNote() -> String {
        switch lang {
        case "es":    return "Se han evitado movimientos de carga espinal pesada para cuidar tu espalda."
        case "it":    return "I movimenti con carico spinale pesante sono stati evitati per proteggere la schiena."
        case "pt-BR": return "Movimentos com carga espinal pesada foram evitados para proteger suas costas."
        case "fr":    return "Les mouvements avec charge spinale lourde ont été évités pour protéger ton dos."
        default:      return "Heavy spinal loading movements have been avoided to protect your back."
        }
    }

    private static func shoulderNote() -> String {
        switch lang {
        case "es":    return "Se han ajustado los presses por encima de la cabeza para proteger tus hombros."
        case "it":    return "I press sopra la testa sono stati adattati per proteggere le spalle."
        case "pt-BR": return "Os exercícios acima da cabeça foram ajustados para proteger seus ombros."
        case "fr":    return "Les développés au-dessus de la tête ont été adaptés pour protéger tes épaules."
        default:      return "Overhead presses have been adjusted to protect your shoulders."
        }
    }

    private static func wristNote() -> String {
        switch lang {
        case "es":    return "Los ejercicios que cargan las muñecas se han sustituido por alternativas más seguras."
        case "it":    return "Gli esercizi che caricano i polsi sono stati sostituiti con alternative più sicure."
        case "pt-BR": return "Exercícios que sobrecarregam os punhos foram substituídos por alternativas mais seguras."
        case "fr":    return "Les exercices qui sollicitent les poignets ont été remplacés par des alternatives plus sûres."
        default:      return "Wrist-loading exercises have been replaced with safer alternatives."
        }
    }

    private static func noTimeNote() -> String {
        switch lang {
        case "es":    return "El plan prioriza rutinas cortas y efectivas de 20-30 minutos."
        case "it":    return "Il piano dà la priorità a routine brevi ed efficaci di 20-30 minuti."
        case "pt-BR": return "O plano prioriza rotinas curtas e eficientes de 20-30 minutos."
        case "fr":    return "Le plan privilégie des séances courtes et efficaces de 20-30 minutes."
        default:      return "The plan prioritizes short, effective 20-30 minute routines."
        }
    }

    private static func sittingNote() -> String {
        switch lang {
        case "es":    return "Se han incluido ejercicios de movilidad y estiramientos para contrarrestar el sedentarismo."
        case "it":    return "Sono stati inclusi esercizi di mobilità e stretching per contrastare la sedentarietà."
        case "pt-BR": return "Foram incluídos exercícios de mobilidade e alongamento para combater o sedentarismo."
        case "fr":    return "Des exercices de mobilité et étirements ont été ajoutés pour contrer la sédentarité."
        default:      return "Mobility and stretching exercises have been added to counter long sitting."
        }
    }

    private static func beginnerNote() -> String {
        switch lang {
        case "es":    return "Los ejercicios se han simplificado con regresiones para que aprendas la técnica con seguridad."
        case "it":    return "Gli esercizi sono stati semplificati con regressioni per imparare la tecnica in sicurezza."
        case "pt-BR": return "Os exercícios foram simplificados com regressões para aprender a técnica com segurança."
        case "fr":    return "Les exercices ont été simplifiés avec des régressions pour apprendre la technique en toute sécurité."
        default:      return "Exercises have been simplified with regressions so you can learn proper form safely."
        }
    }

    private static func veganNote() -> String {
        switch lang {
        case "es":    return "Las recomendaciones nutricionales priorizan proteínas vegetales (legumbres, tofu, tempeh, quinoa)."
        case "it":    return "Le raccomandazioni nutrizionali danno priorità alle proteine vegetali (legumi, tofu, tempeh, quinoa)."
        case "pt-BR": return "As recomendações nutricionais priorizam proteínas vegetais (leguminosas, tofu, tempeh, quinoa)."
        case "fr":    return "Les recommandations nutritionnelles privilégient les protéines végétales (légumineuses, tofu, tempeh, quinoa)."
        default:      return "Nutrition recommendations prioritize plant proteins (legumes, tofu, tempeh, quinoa)."
        }
    }

    // MARK: - Day names

    // Day labels for the 7-day plan, rotated so index 0 is the actual current
    // weekday — a plan generated on Thursday starts on Thursday, not Monday.
    static var days: [String] {
        let weekdays: [String]
        switch lang {
        case "es":
            weekdays = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
        case "it":
            weekdays = ["Domenica", "Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato"]
        case "pt-BR":
            weekdays = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
        case "fr":
            weekdays = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
        default:
            weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        }
        // Calendar weekday: 1 = Sunday … 7 = Saturday → 0-based index.
        let todayIndex = Calendar.current.component(.weekday, from: Date()) - 1
        return (0..<7).map { offset in weekdays[(todayIndex + offset) % 7] }
    }

    // MARK: - Rest day activities

    static func activeRecoveryExercises() -> [String] {
        switch lang {
        case "es":    return ["Caminata rápida 30 min", "Estiramientos 10 min", "Foam roller piernas y espalda"]
        case "it":    return ["Camminata veloce 30 min", "Stretching 10 min", "Foam roller gambe e schiena"]
        case "pt-BR": return ["Caminhada rápida 30 min", "Alongamento 10 min", "Foam roller pernas e costas"]
        case "fr":    return ["Marche rapide 30 min", "Étirements 10 min", "Foam roller jambes et dos"]
        default:      return ["30-min brisk walk", "10-min full-body stretch", "Foam roll legs & back"]
        }
    }

    static func lightRecoveryExercises() -> [String] {
        switch lang {
        case "es":    return ["Trote suave 20 min o bicicleta", "Yoga o estiramientos 10 min"]
        case "it":    return ["Jogging leggero 20 min o bici", "Yoga o stretching 10 min"]
        case "pt-BR": return ["Trote leve 20 min ou bicicleta", "Yoga ou alongamento 10 min"]
        case "fr":    return ["Jogging léger 20 min ou vélo", "Yoga ou étirements 10 min"]
        default:      return ["20-min light jog or cycling", "10-min yoga or stretching"]
        }
    }

    static func fullRestExercises() -> [String] {
        switch lang {
        case "es":    return ["Descanso y recuperación", "Caminata suave si lo deseas", "Prepara comidas para la semana"]
        case "it":    return ["Riposo e recupero", "Camminata leggera se vuoi", "Prepara i pasti per la settimana"]
        case "pt-BR": return ["Descanso e recuperação", "Caminhada leve se desejar", "Prepare as refeições da semana"]
        case "fr":    return ["Repos et récupération", "Marche légère si souhaité", "Prépare tes repas pour la semaine"]
        default:      return ["Rest & recover", "Light walk if desired", "Prep meals for the week"]
        }
    }

    // MARK: - ExtraContext processing

    private static func applyContext(_ schedule: [DayPlan], context: String) -> [DayPlan] {
        let hasKnee     = hasKneeKeyword(context)
        let hasShoulder = hasShoulderKeyword(context)
        let hasWrist    = hasWristKeyword(context)
        let hasHome     = hasHomeKeyword(context)
        let hasBack     = hasBackKeyword(context)
        let hasBeginner = hasBeginnerKeyword(context)
        let hasSitting  = hasSittingKeyword(context)
        let hasNoTime   = hasNoTimeKeyword(context)

        guard hasKnee || hasShoulder || hasWrist || hasHome || hasBack
              || hasBeginner || hasSitting || hasNoTime else { return schedule }

        // Active substitution sets, applied in priority order. Home equipment
        // first, then injury swaps, then beginner regressions.
        var activeSets: [[(String, String)]] = []
        if hasHome     { activeSets.append(homeSubs) }
        if hasKnee     { activeSets.append(kneeSubs) }
        if hasShoulder { activeSets.append(shoulderSubs) }
        if hasWrist    { activeSets.append(wristSubs) }
        if hasBack     { activeSets.append(backSubs) }
        if hasBeginner { activeSets.append(beginnerSubs) }

        // Apply every active set repeatedly until the exercise stops changing.
        // This is the key fix: one injury's replacement can be another injury's
        // forbidden move (e.g. shoulder swaps Bench Press → Leg Press, which a
        // bad knee must then swap to Glute Bridge). A single pass missed that.
        func makeSafe(_ exercise: String) -> String {
            var current = exercise
            for _ in 0..<6 {   // converges well before 6; cap guards against cycles
                var next = current
                for set in activeSets {
                    next = substitute(next, with: set)
                }
                if next == current { break }
                current = next
            }
            return current
        }

        // Many unsafe moves share one safe replacement (a bad knee turns squats,
        // lunges and leg presses into glute bridges), so a day could list the
        // same exercise three times. A repeat becomes the closest alternative
        // the active limits allow, or is dropped when none fits.
        func withoutRepeats(_ exercises: [String]) -> [String] {
            var seen = Set<String>()
            return exercises.compactMap { ex in
                let name = WeeklyPlanner.exerciseName(of: ex)
                if seen.insert(name.lowercased()).inserted { return ex }
                let suffix = String(ex.dropFirst(name.count))
                let options = (repeatAlternatives[name] ?? []) + generalAlternatives
                guard let alt = options.first(where: { makeSafe($0) == $0 && !seen.contains($0.lowercased()) })
                else { return nil }
                seen.insert(alt.lowercased())
                return alt + suffix
            }
        }

        return schedule.map { day -> DayPlan in
            var day = day
            var modifiedExercises = withoutRepeats(day.exercises.map(makeSafe))
            // Short-on-time: trim each workout to the first 4 (compound) moves so
            // sessions fit in ~20-30 min — the note promised it, now we deliver it.
            if hasNoTime && day.isWorkout && modifiedExercises.count > 4 {
                modifiedExercises = Array(modifiedExercises.prefix(4))
            }
            // For sedentary users, append a mobility move to workout days.
            if hasSitting && day.isWorkout {
                modifiedExercises.append(mobilityExerciseName())
            }
            // Copying the day keeps its intensity; rebuilding it lost it.
            day.exercises = modifiedExercises
            return day
        }
    }

    private static func hasKneeKeyword(_ ctx: String) -> Bool {
        ["knee", "rodilla", "ginocchio", "genou", "joelho", "knie"].contains { ctx.contains($0) }
    }

    private static func hasHomeKeyword(_ ctx: String) -> Bool {
        ["home", "casa", "maison", "chez moi", "domicilio", "casa mia"].contains { ctx.contains($0) }
    }

    private static func hasBackKeyword(_ ctx: String) -> Bool {
        ["back pain", "dolor de espalda", "mal au dos", "mal di schiena", "dor nas costas",
         "bad back", "espalda", "schiena", "costas"].contains { ctx.contains($0) }
    }

    private static func hasShoulderKeyword(_ ctx: String) -> Bool {
        ["shoulder", "hombro", "spalla", "épaule", "epaule", "ombro"]
            .contains { ctx.contains($0) }
    }

    private static func hasWristKeyword(_ ctx: String) -> Bool {
        ["wrist", "muñeca", "muneca", "polso", "poignet", "punho"]
            .contains { ctx.contains($0) }
    }

    private static func hasNoTimeKeyword(_ ctx: String) -> Bool {
        ["no time", "busy", "poco tiempo", "ocupado", "pas de temps", "occupé",
         "poco tempo", "occupato", "sem tempo", "ocupado", "rapido", "rapide",
         "quick", "fast"].contains { ctx.contains($0) }
    }

    private static func hasSittingKeyword(_ ctx: String) -> Bool {
        ["sitting", "sedentary", "desk", "office", "sentado", "sedentario",
         "oficina", "escritorio", "seduto", "scrivania", "assis", "bureau",
         "sentado", "escritório"].contains { ctx.contains($0) }
    }

    private static func hasBeginnerKeyword(_ ctx: String) -> Bool {
        ["beginner", "first time", "new", "principiante", "primera vez", "nuevo",
         "principiant", "première", "débutant", "debutant", "principiante",
         "iniziato", "iniciante", "novato", "starting"]
            .contains { ctx.contains($0) }
    }

    static func hasVeganKeyword(_ ctx: String) -> Bool {
        ["vegan", "vegano", "vegana", "végan", "vegano",
         "vegetarian", "vegetariano", "vegetariana", "végétarien", "vegetariano"]
            .contains { ctx.contains($0) }
    }

    // Match on the exercise name and replace the WHOLE name, keeping sets/reps
    // ("Squat 5×5" → "Glute Bridge 5×5"). Replacing only the matched text
    // turned "Back Squat" into "Back Glute Bridge". Longer keys win so
    // "Romanian Deadlift" beats "Deadlift".
    private static func substitute(_ ex: String, with subs: [(String, String)]) -> String {
        let name = WeeklyPlanner.exerciseName(of: ex)
        let suffix = String(ex.dropFirst(name.count))
        let sorted = subs.sorted { $0.0.count > $1.0.count }
        for (key, replacement) in sorted where name.range(of: key, options: .caseInsensitive) != nil {
            return replacement + suffix
        }
        return ex
    }

    // MARK: - Substitution dictionaries

    /// Closest stand-ins for a replacement that already appears that day.
    private static let repeatAlternatives: [String: [String]] = [
        "Glute Bridge":          ["Single-Leg Glute Bridge", "Hip Abduction", "Bird Dog"],
        "Leg Press":             ["Leg Extension", "Seated Calf Raise", "Glute Bridge"],
        "Leg Extension":         ["Seated Calf Raise", "Glute Bridge", "Hip Abduction"],
        "Seated Dumbbell Press": ["Dumbbell Lateral Raise", "Face Pull", "Band Pull-Apart"],
        "Seated Shoulder Press": ["Dumbbell Lateral Raise", "Face Pull", "Band Pull-Apart"],
        "Hammer Curl":           ["Incline Dumbbell Curl", "Cable Curl (strap)"],
        "Tricep Pushdown":       ["Dumbbell Overhead Extension", "Tricep Kickback"],
        "Chest-Supported Row":   ["Lat Pulldown", "Face Pull"],
        "Dead Bug":              ["Bird Dog", "Lying Leg Raise"],
        "Push-ups":              ["Incline Push-up", "Knee Push-up"],
    ]
    /// Light core and posture work that fits almost any limit.
    private static let generalAlternatives = ["Bird Dog", "Dead Bug", "Hip Abduction", "Band Pull-Apart"]

    // KNEE: the knee should rest, so anything that bends/loads it becomes an
    // UPPER-BODY or core move that doesn't involve the knee at all.
    private static let kneeSubs: [(String, String)] = [
        ("Jump Rope",           "Seated Shoulder Press"),
        ("High Knees",          "Seated Shoulder Press"),
        ("Burpees",             "Push-ups"),
        ("Box Jump",            "Seated Dumbbell Press"),
        ("Walking Lunge",       "Glute Bridge"),
        ("Reverse Lunge",       "Glute Bridge"),
        ("Goblet Squat",        "Glute Bridge"),
        ("Wall Squat",          "Glute Bridge"),
        ("Pistol Squat",        "Glute Bridge"),
        ("Leg Press",           "Glute Bridge"),
        ("Leg Curl",            "Glute Bridge"),
        ("Leg Extension",       "Glute Bridge"),
        ("Romanian Deadlift",   "Glute Bridge"),
        ("Squat",               "Glute Bridge"),
        ("Step-up",             "Glute Bridge"),
        ("Calf Raise",          "Seated Calf Raise"),
        ("Mountain Climber",   "Plank"),
        ("Running",             "Seated Row"),
    ]

    // BACK: protect the spine — no axial loading, no hip-hinge under load.
    // Swaps go to supported / lying movements that spare the lower back.
    private static let backSubs: [(String, String)] = [
        ("Clean and Press",     "Seated Dumbbell Press"),
        ("Romanian Deadlift",   "Leg Extension"),
        ("Deadlift",            "Leg Extension"),
        ("Pendlay Row",         "Chest-Supported Row"),
        ("Barbell Row",         "Chest-Supported Row"),
        ("Bent-over Row",       "Chest-Supported Row"),
        ("Clean & Press",       "Seated Dumbbell Press"),
        ("Back Squat",          "Leg Extension"),
        ("Goblet Squat",        "Leg Extension"),
        ("Squat",               "Leg Extension"),
        ("Overhead Press",      "Seated Dumbbell Press"),
        ("Push Press",          "Seated Dumbbell Press"),
        ("Russian Twist",       "Dead Bug"),
        ("Sit-up",              "Dead Bug"),
        ("Crunch",              "Dead Bug"),
        ("Leg Raise",           "Dead Bug"),
        ("Good Morning",        "Glute Bridge"),
        ("Box Jump",            "Seated Calf Raise"),
    ]

    // SHOULDER: rest the shoulder — no pressing/overhead/raises. Swaps focus on
    // legs, back-via-machine, and arms in a neutral position.
    private static let shoulderSubs: [(String, String)] = [
        ("Overhead Press",          "Leg Press"),
        ("Arnold Press",            "Leg Press"),
        ("Push Press",              "Leg Press"),
        ("Dumbbell Push Press",     "Leg Press"),
        ("Pike Push-up",            "Glute Bridge"),
        ("Bench Press",             "Leg Press"),
        ("Incline Bench",           "Leg Press"),
        ("Incline DB Press",        "Leg Press"),
        ("Incline Dumbbell Press",  "Leg Press"),
        ("Close-grip Bench",        "Tricep Pushdown"),
        ("Push-up",                 "Glute Bridge"),
        ("Lateral Raise",           "Hammer Curl"),
        ("Front Raise",             "Hammer Curl"),
        ("Skull Crusher",           "Tricep Pushdown"),
        ("Face Pull",               "Lat Pulldown"),
        ("Upright Row",             "Lat Pulldown"),
    ]

    // WRIST: no weight-bearing on the hands and no gripping-heavy work.
    private static let wristSubs: [(String, String)] = [
        ("Barbell Hip Thrust",  "Glute Bridge"),
        ("Push-up",            "Leg Press"),
        ("Plank",              "Dead Bug"),
        ("Mountain Climber",  "Glute Bridge"),
        ("Burpees",            "Glute Bridge"),
        ("Dumbbell Curl",      "Cable Curl (strap)"),
        ("Barbell Curl",       "Cable Curl (strap)"),
        ("Hammer Curl",        "Cable Curl (strap)"),
        ("Skull Crusher",      "Tricep Pushdown (rope)"),
        ("Tricep Dip",         "Tricep Pushdown (rope)"),
        ("Pike Push-up",       "Leg Press"),
        ("Pull-up",           "Lat Pulldown (straps)"),
        ("Deadlift",           "Leg Press"),
    ]

    // HOME / no equipment: replace barbells & machines with dumbbell or
    // bodyweight alternatives.
    private static let homeSubs: [(String, String)] = [
        ("Back Squat",          "Goblet Squat"),
        ("Barbell Hip Thrust",  "Glute Bridge"),
        ("Overhead Press",      "Seated Dumbbell Press"),
        ("Hanging Leg Raise",   "Lying Leg Raise"),
        ("Clean and Press",     "Dumbbell Clean & Press"),
        ("Barbell Row",         "Dumbbell Row"),
        ("Pendlay Row",         "Dumbbell Row"),
        ("Seated Row",          "Resistance Band Row"),
        ("Barbell Curl",        "Dumbbell Curl"),
        ("Preacher Curl",       "Incline Dumbbell Curl"),
        ("Bench Press",         "Dumbbell Press (floor)"),
        ("Incline Bench",       "Incline Push-up"),
        ("Lat Pulldown",        "Resistance Band Pulldown"),
        ("Cable Fly",           "Dumbbell Fly"),
        ("Cable Lateral Raise", "Dumbbell Lateral Raise"),
        ("Tricep Pushdown",     "Tricep Kickback"),
        ("Skull Crusher",       "Dumbbell Overhead Extension"),
        ("Leg Press",           "Goblet Squat"),
        ("Leg Curl",            "Nordic Curl"),
        ("Hack Squat",          "Goblet Squat"),
        ("Clean & Press",       "Dumbbell Clean & Press"),
        ("Deadlift",            "Romanian Deadlift (dumbbells)"),
        ("Pull-up",            "Resistance Band Pulldown"),
    ]

    // BEGINNER: regressions for moves that need solid form first.
    private static let beginnerSubs: [(String, String)] = [
        ("Clean and Press",     "Dumbbell Push Press (light)"),
        ("Weighted Pull-ups",   "Lat Pulldown"),
        ("Pull-up",            "Assisted Pull-ups"),
        ("Chin-ups",            "Assisted Chin-ups"),
        ("Burpees",             "Squat-to-Stand"),
        ("Box Jump",            "Step-up"),
        ("Pistol Squat",        "Bodyweight Squat"),
        ("Deadlift",            "Romanian Deadlift (light)"),
        ("Push-up",             "Knee Push-up"),
        ("Pike Push-up",        "Incline Push-up"),
        ("Plank",               "Knee Plank"),
        ("Mountain Climber",   "Marching Plank"),
        ("Clean & Press",       "Dumbbell Push Press (light)"),
    ]
    private static func mobilityExerciseName() -> String {
        let options: [String]
        switch lang {
        case "es":    options = ["Movilidad de cadera 3×30 sec", "Estiramiento de espalda 3×30 sec",
                                 "Cat-cow 3×10", "World's greatest stretch 2×6"]
        case "it":    options = ["Mobilità d'anca 3×30 sec", "Stretching schiena 3×30 sec",
                                 "Cat-cow 3×10", "World's greatest stretch 2×6"]
        case "pt-BR": options = ["Mobilidade de quadril 3×30 seg", "Alongamento de costas 3×30 seg",
                                 "Cat-cow 3×10", "World's greatest stretch 2×6"]
        case "fr":    options = ["Mobilité de hanches 3×30 sec", "Étirement du dos 3×30 sec",
                                 "Cat-cow 3×10", "World's greatest stretch 2×6"]
        default:      options = ["Hip mobility 3×30 sec", "Back stretch 3×30 sec",
                                 "Cat-cow 3×10", "World's greatest stretch 2×6"]
        }
        return options.randomElement() ?? options[0]
    }

    // MARK: - Nutrition

    static func nutritionTips(goal: FitnessGoal) -> [String] {
        switch (goal, lang) {
        case (.loseWeight, "es"):
            return ["Come proteínas en cada comida para mantener la saciedad y preservar músculo",
                    "Bebe 3 L de agua al día. El hambre suele ser sed disfrazada",
                    "Prioriza verduras y fibra para reducir el hambre con déficit calórico",
                    "Evita calorías líquidas: jugos, refrescos y alcohol suman rápido",
                    "Prepara comidas el domingo para evitar elecciones impulsivas durante la semana"]
        case (.gainMuscle, "es"):
            return ["Come 30-40 g de proteína en los 45 min posteriores al entrenamiento",
                    "Distribuye la proteína en 4-5 comidas para maximizar la síntesis muscular",
                    "No omitas los carbohidratos. Alimentan tu entrenamiento y la recuperación",
                    "Bebe al menos 3 L de agua al día; el músculo es 75% agua",
                    "Considera un batido de caseína antes de dormir para alimentar los músculos de noche"]
        case (.stayFit, "es"):
            return ["Sigue la regla 80/20: 80% alimentos reales, 20% flexibilidad",
                    "Incluye omega-3 (salmón, nueces) para la salud articular y reducir inflamación",
                    "Bebe 2.5-3 L de agua al día",
                    "Come 5 o más porciones de verduras y frutas al día",
                    "Mantén horarios de comidas consistentes para regular las hormonas del hambre"]
        case (.loseWeight, "it"):
            return ["Mangia proteine ad ogni pasto per restare sazio e preservare il muscolo",
                    "Bevi 3 L d'acqua al giorno. Spesso la fame è sete travestita",
                    "Privilegia verdure e fibre per ridurre la fame con deficit calorico",
                    "Evita le calorie liquide: succhi, bevande gassate e alcol si accumulano velocemente",
                    "Prepara i pasti la domenica per evitare scelte impulsive durante la settimana"]
        case (.gainMuscle, "it"):
            return ["Consuma 30-40 g di proteine entro 45 minuti dall'allenamento",
                    "Distribuisci le proteine in 4-5 pasti per massimizzare la sintesi muscolare",
                    "Non saltare i carboidrati. Alimentano l'allenamento e il recupero",
                    "Bevi almeno 3 L d'acqua al giorno; il muscolo è composto al 75% d'acqua",
                    "Considera un frullato di caseina prima di dormire per nutrire i muscoli di notte"]
        case (.stayFit, "it"):
            return ["Segui la regola 80/20: 80% cibi interi, 20% flessibilità",
                    "Includi omega-3 (salmone, noci) per la salute delle articolazioni",
                    "Bevi 2.5-3 L d'acqua al giorno",
                    "Mangia 5 o più porzioni di verdure e frutta al giorno",
                    "Mantieni orari dei pasti costanti per regolare gli ormoni della fame"]
        case (.loseWeight, "pt-BR"):
            return ["Coma proteínas em cada refeição para manter a saciedade e preservar músculo",
                    "Beba 3 L de água por dia. A fome muitas vezes é sede disfarçada",
                    "Priorize vegetais e fibras para reduzir a fome com déficit calórico",
                    "Evite calorias líquidas: sucos, refrigerantes e álcool somam rápido",
                    "Prepare refeições no domingo para evitar escolhas impulsivas durante a semana"]
        case (.gainMuscle, "pt-BR"):
            return ["Coma 30-40 g de proteína nos 45 minutos após o treino",
                    "Distribua a proteína em 4-5 refeições para maximizar a síntese muscular",
                    "Não pule os carboidratos. Eles alimentam seu treino e a recuperação",
                    "Beba pelo menos 3 L de água por dia; o músculo é 75% água",
                    "Considere um shake de caseína antes de dormir para nutrir os músculos à noite"]
        case (.stayFit, "pt-BR"):
            return ["Siga a regra 80/20: 80% alimentos naturais, 20% flexibilidade",
                    "Inclua ômega-3 (salmão, nozes) para saúde articular e reduzir inflamação",
                    "Beba 2,5-3 L de água por dia",
                    "Coma 5 ou mais porções de vegetais e frutas por dia",
                    "Mantenha horários de refeições consistentes para regular os hormônios da fome"]
        case (.loseWeight, "fr"):
            return ["Mange des protéines à chaque repas pour rester rassasié et préserver le muscle",
                    "Bois 3 L d'eau par jour. La faim est souvent de la soif déguisée",
                    "Privilégie les légumes et les fibres pour réduire la faim en déficit calorique",
                    "Évite les calories liquides : jus, sodas et alcool s'accumulent vite",
                    "Prépare tes repas le dimanche pour éviter les choix impulsifs en semaine"]
        case (.gainMuscle, "fr"):
            return ["Consomme 30-40 g de protéines dans les 45 min après l'entraînement",
                    "Répartis les protéines sur 4-5 repas pour maximiser la synthèse musculaire",
                    "Ne saute pas les glucides. Ils alimentent tes séances et la récupération",
                    "Bois au moins 3 L d'eau par jour ; le muscle est composé à 75% d'eau",
                    "Pense à un shake de caséine avant de dormir pour nourrir les muscles la nuit"]
        case (.stayFit, "fr"):
            return ["Suis la règle 80/20 : 80% d'aliments naturels, 20% de flexibilité",
                    "Inclus des oméga-3 (saumon, noix) pour la santé articulaire",
                    "Bois 2,5-3 L d'eau par jour",
                    "Mange 5 portions ou plus de légumes et de fruits par jour",
                    "Maintiens des horaires de repas réguliers pour équilibrer les hormones de la faim"]
        case (.loseWeight, _):
            return ["Eat protein in every meal to stay full and preserve muscle",
                    "Drink 3 L of water per day. Hunger is often thirst in disguise",
                    "Prioritise vegetables and fibre to reduce hunger on a deficit",
                    "Avoid liquid calories: juices, sodas, and alcohol add up fast",
                    "Meal-prep on Sunday to avoid impulsive food choices during the week"]
        case (.gainMuscle, _):
            return ["Eat 30-40 g of protein within 45 minutes post-workout",
                    "Spread protein intake evenly across 4-5 meals for maximum synthesis",
                    "Don't skip carbs: they fuel your workouts and aid recovery",
                    "Drink at least 3 L of water daily; muscles are 75% water",
                    "Consider a casein protein shake before bed to feed muscles overnight"]
        case (.stayFit, _):
            return ["Follow the 80/20 rule: 80% whole foods, 20% flexibility",
                    "Include omega-3s (salmon, walnuts) for joint health and inflammation",
                    "Drink 2.5-3 L of water daily",
                    "Eat 5+ servings of vegetables and fruits per day",
                    "Aim for consistent meal times to regulate hunger hormones"]
        }
    }

    // MARK: - Tips

    private static func tips(goal: FitnessGoal) -> [String] {
        switch (goal, lang) {
        case (.loseWeight, "es"):
            return ["Duerme 7-9 horas: el mal sueño aumenta las hormonas del hambre hasta un 30%",
                    "Toma fotos de progreso cada 2 semanas, no solo la báscula. El músculo pesa más que la grasa",
                    "Añade caminatas de 10 min después de las comidas para potenciar la quema de grasa",
                    "Sube el peso un 2.5-5% cuando completes todas las repeticiones con buena técnica"]
        case (.gainMuscle, "es"):
            return ["Registra tus levantamientos en cada sesión. La sobrecarga progresiva es el motor nº1 del crecimiento muscular",
                    "Duerme 8+ horas: el 70% de la hormona del crecimiento se libera durante el sueño profundo",
                    "Descansa 2-3 min entre series pesadas para una recuperación completa de fuerza",
                    "Descarga cada 6-8 semanas: reduce el volumen un 40% para que tendones y articulaciones se recuperen"]
        case (.stayFit, "es"):
            return ["La consistencia supera la intensidad. 3 Sesiones moderadas a la semana valen más que una brutal",
                    "Incluye trabajo de movilidad dos veces por semana para prevenir lesiones y mejorar el rendimiento",
                    "Monitorea tus niveles de energía. Ajusta los días de descanso según cómo se siente tu cuerpo",
                    "Varía el cardio (bicicleta, natación, running) para evitar el aburrimiento y las lesiones"]
        case (.loseWeight, "it"):
            return ["Dormi 7-9 ore: il sonno scarso aumenta gli ormoni della fame fino al 30%",
                    "Scatta foto di progresso ogni 2 settimane. Il muscolo pesa più del grasso",
                    "Aggiungi camminate di 10 min dopo i pasti per potenziare la combustione dei grassi",
                    "Aumenta i pesi del 2.5-5% quando riesci a completare tutte le ripetizioni con buona forma"]
        case (.gainMuscle, "it"):
            return ["Registra i tuoi sollevamenti ad ogni sessione. Il sovraccarico progressivo è il principale motore della crescita muscolare",
                    "Dormi 8+ ore: il 70% dell'ormone della crescita viene rilasciato durante il sonno profondo",
                    "Riposati 2-3 min tra le serie pesanti per un recupero completo della forza",
                    "Scarica ogni 6-8 settimane: riduci il volume del 40%"]
        case (.stayFit, "it"):
            return ["La costanza supera l'intensità. 3 Sessioni moderate a settimana valgono più di una brutale",
                    "Includi lavoro di mobilità due volte a settimana per prevenire infortuni",
                    "Monitora i tuoi livelli di energia. Adatta i giorni di riposo in base a come si sente il tuo corpo",
                    "Varia il cardio (ciclismo, nuoto, corsa) per evitare noia e infortuni"]
        case (.loseWeight, "pt-BR"):
            return ["Durma 7-9 horas: o sono ruim aumenta os hormônios da fome em até 30%",
                    "Tire fotos de progresso a cada 2 semanas. Músculo pesa mais que gordura",
                    "Adicione caminhadas de 10 min após as refeições para potencializar a queima de gordura",
                    "Aumente o peso em 2,5-5% quando completar todas as repetições com boa forma"]
        case (.gainMuscle, "pt-BR"):
            return ["Registre seus levantamentos em cada sessão. A sobrecarga progressiva é o principal motor do crescimento muscular",
                    "Durma 8+ horas: 70% do hormônio do crescimento é liberado durante o sono profundo",
                    "Descanse 2-3 min entre séries pesadas para recuperação completa de força",
                    "Faça deload a cada 6-8 semanas: reduza o volume em 40%"]
        case (.stayFit, "pt-BR"):
            return ["Consistência supera intensidade: 3 sessões moderadas por semana valem mais do que uma brutal",
                    "Inclua trabalho de mobilidade duas vezes por semana para prevenir lesões",
                    "Monitore seus níveis de energia. Ajuste os dias de descanso conforme seu corpo",
                    "Varie o cardio (bike, natação, corrida) para evitar tédio e lesões"]
        case (.loseWeight, "fr"):
            return ["Dors 7-9 heures: le manque de sommeil augmente les hormones de la faim jusqu'à 30%",
                    "Prends des photos de progression toutes les 2 semaines. Le muscle pèse plus que la graisse",
                    "Ajoute des marches de 10 min après les repas pour booster la combustion des graisses",
                    "Augmente les charges de 2,5-5% quand tu complètes toutes les reps avec une bonne forme"]
        case (.gainMuscle, "fr"):
            return ["Note tes soulevés à chaque séance. La surcharge progressive est le principal moteur de la croissance musculaire",
                    "Dors 8+ heures: 70% de l'hormone de croissance est libérée pendant le sommeil profond",
                    "Repose-toi 2-3 min entre les séries lourdes pour une récupération complète de la force",
                    "Fais un décharge toutes les 6-8 semaines : réduis le volume de 40%"]
        case (.stayFit, "fr"):
            return ["La régularité bat l'intensité. 3 Séances modérées par semaine valent mieux qu'une séance brutale",
                    "Inclus du travail de mobilité deux fois par semaine pour prévenir les blessures",
                    "Surveille ton niveau d'énergie. Adapte les jours de repos selon ce que ressent ton corps",
                    "Varie le cardio (vélo, natation, course) pour éviter l'ennui et les blessures"]
        case (.loseWeight, _):
            return ["Sleep 7-9 hours: poor sleep increases hunger hormones by up to 30%",
                    "Take progress photos every 2 weeks, not just the scale. Muscle weighs more than fat",
                    "Add 10-minute walks after meals to boost fat burning and digestion",
                    "Increase weights by 2.5-5% when you can complete all reps with good form"]
        case (.gainMuscle, _):
            return ["Log your lifts every session. Progressive overload is the #1 driver of muscle growth",
                    "Sleep 8+ hours: 70% of growth hormone is released during deep sleep",
                    "Rest 2-3 min between heavy compound sets for full strength recovery",
                    "Deload every 6-8 weeks: reduce volume by 40% to let your tendons and joints recover"]
        case (.stayFit, _):
            return ["Consistency beats intensity: 3 moderate sessions per week beat 1 brutal one",
                    "Include mobility work twice a week to prevent injury and improve performance",
                    "Track your energy levels. Adjust rest days based on how your body feels",
                    "Vary your cardio (cycling, swimming, running) to prevent boredom and overuse injuries"]
        }
    }

    // MARK: - Motivation

    private static func motivation(goal: FitnessGoal) -> String {
        // Three phrasings per goal — one picked at random per generation.
        let variant = ["", ".v2", ".v3"].randomElement() ?? ""
        let key: String
        switch goal {
        case .loseWeight: key = "coach.motivation.loseWeight"
        case .gainMuscle: key = "coach.motivation.gainMuscle"
        case .stayFit:    key = "coach.motivation.stayFit"
        }
        return NSLocalizedString(key + variant, comment: "")
    }
}
