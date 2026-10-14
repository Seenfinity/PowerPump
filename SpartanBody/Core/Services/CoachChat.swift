import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

// The coach chat. Answers come from Apple's on-device language model when the
// iPhone has Apple Intelligence; otherwise from CoachFAQ, a set of answers to
// the common questions filled with the user's own numbers. Either way nothing
// leaves the phone.

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, coach }
    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    /// Buttons under a Spartan message (shorten today, change dinner…).
    var actions: [ChatAction]? = nil
}

@MainActor
final class CoachChatStore: ObservableObject {
    static let shared = CoachChatStore()

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isResponding = false
    /// Questions to offer after Spartan's last answer.
    @Published private(set) var followUps: [String] = []
    /// A post-workout recap waiting to be shown outside the chat.
    @Published var pendingRecap: UUID?

    enum Mode: Equatable {
        case appleIntelligence
        /// Basic answers; the key explains why the full coach isn't available.
        case basic(reasonKey: String)
    }

    private let key = "sb_coach_chat"
    private var engine: AnyObject?

    private init() {
        messages = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([ChatMessage].self, from: $0) } ?? []
        NotificationCenter.default.addObserver(forName: .sbWorkoutFinished, object: nil, queue: .main) { note in
            guard let id = note.object as? UUID else { return }
            MainActor.assumeIsolated { CoachChatStore.shared.recap(sessionID: id) }
        }
    }

    /// Spartan comments on a session the moment it's saved.
    func recap(sessionID: UUID) {
        guard let session = WorkoutStore.shared.history.first(where: { $0.id == sessionID }) else { return }
        let r = SpartanActions.recap(session)
        let m = ChatMessage(role: .coach, text: r.text, actions: r.actions)
        messages.append(m)
        pendingRecap = m.id
        save()
    }

    /// Runs one of the buttons under a Spartan message.
    func perform(_ action: ChatAction, in messageID: UUID) {
        guard let i = messages.firstIndex(where: { $0.id == messageID }),
              messages[i].actions?.contains(where: { $0.id == action.id && !$0.done }) == true else { return }
        // Alternatives (ease or move, an RPE) are one choice. A meal swap and a
        // rebuild of the week are separate, and a rebuild makes the swaps moot.
        messages[i].actions = messages[i].actions?.map { a in
            var a = a
            switch action.kind {
            case .swapMeal: if a.id == action.id { a.done = true }
            case .rebuild:  if a.kind == .rebuild || a.kind == .swapMeal { a.done = true }
            default:        if a.kind != .rebuild { a.done = true }
            }
            return a
        }
        HapticManager.success()
        messages.append(ChatMessage(role: .coach, text: SpartanActions.perform(action)))
        switch action.kind {
        case .rpe:            followUps = []
        case .ease, .move:    followUps = SpartanVoice.followUps(after: .sleep)
        case .shorten:        followUps = SpartanVoice.followUps(after: .trainToday)
        case .swapMeal, .rebuild: followUps = SpartanVoice.followUps(after: .eatToday)
        }
        save()
    }

    var mode: Mode {
        #if DEBUG
        // Lets a development build show what an iPhone without Apple
        // Intelligence sees (`-sb_force_basic YES` as a launch argument).
        if UserDefaults.standard.bool(forKey: "sb_force_basic") { return .basic(reasonKey: "chat.basic.device") }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return model.supportsLocale() ? .appleIntelligence : .basic(reasonKey: "chat.basic.language")
            case .unavailable(.appleIntelligenceNotEnabled): return .basic(reasonKey: "chat.basic.enable")
            case .unavailable(.modelNotReady):               return .basic(reasonKey: "chat.basic.downloading")
            default:                                         return .basic(reasonKey: "chat.basic.device")
            }
        }
        #endif
        return .basic(reasonKey: "chat.basic.ios")
    }

    /// Loads the model ahead of the first question so the reply starts sooner.
    func prepare() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), mode == .appleIntelligence { onDevice.prewarm() }
        #endif
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        messages.append(ChatMessage(role: .user, text: text))
        let reply = ChatMessage(role: .coach, text: "")
        messages.append(reply)
        isResponding = true

        followUps = []
        Task {
            let topic = CoachTopic.detect(text)
            // Momentary requests ("I'm tired today") aren't facts to keep;
            // a dislike in "change my dinner" is.
            let momentary: Set<CoachTopic> = [.shortToday, .easyToday, .moveWorkout]
            let learned = topic.map(momentary.contains) == true ? [] : SpartanMemory.shared.learn(from: text)
            var extraActions: [ChatAction] = []
            if let rebuild = SpartanActions.rebuildOffer(for: learned) { extraActions.append(rebuild) }
            @MainActor func attach(_ actions: [ChatAction]) {
                guard !actions.isEmpty, let i = messages.firstIndex(where: { $0.id == reply.id }) else { return }
                messages[i].actions = actions
            }
            // Requests that change the plan: answered locally, with buttons.
            if let offer = SpartanActions.offer(for: topic, message: text) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                // A request, not a question: no "good question" opener, and a
                // dislike is already acknowledged in the offer itself.
                update(reply.id, SpartanVoice.wrap(offer.text, topic: topic,
                                                   learned: topic == .swapMeal ? [] : learned, opener: false))
                // A plan rebuild already covers what a dislike's own button does.
                attach(offer.actions + extraActions.filter { a in !offer.actions.contains { $0.kind == a.kind } })
                isResponding = false
                followUps = []
                save()
                return
            }
            // Defers run last-first: the buttons are attached before saving.
            defer {
                isResponding = false
                followUps = SpartanVoice.followUps(after: CoachTopic.secondary(text, besides: topic) ?? topic)
                save()
            }
            defer { attach(extraActions) }
            // Exercise and food questions come from the app's own tables; only
            // when the item isn't there does the model (if any) take over.
            let fromTables = topic.map(SpartanKnowledge.topics.contains) == true
            let knowledge = fromTables ? SpartanKnowledge.answer(topic, question: text) : nil
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), mode == .appleIntelligence,
               topic?.isCurated != true || (fromTables && knowledge == nil) {
                // Something new learned: Spartan says so before answering.
                let ack = learned.isEmpty ? "" : SpartanVoice.pick("spartan.learned.\(SpartanStyle.current.rawValue)") + "\n\n"
                let ok = await onDevice.reply(to: text, history: Array(messages.dropLast(2))) { [weak self] partial in
                    self?.update(reply.id, ack + partial)
                }
                // An empty answer counts as a failure too.
                if ok, let i = messages.firstIndex(where: { $0.id == reply.id }), !messages[i].text.isEmpty {
                    // The model doesn't always use what it was told about the
                    // user; Spartan adds it himself so the answer is theirs.
                    let extra = [SpartanVoice.memoryLine(for: topic), SpartanInsights.line(for: topic).map(SpartanVoice.linked)]
                        .compactMap { $0 }.filter { !messages[i].text.contains($0) }
                    if topic != nil, !extra.isEmpty {
                        messages[i].text += "\n\n" + extra.joined(separator: "\n\n")
                    }
                    return
                }
            }
            #endif
            // A short pause so a fixed answer doesn't feel like a canned reply.
            try? await Task.sleep(nanoseconds: 600_000_000)
            let context = CoachContext.current()
            let second = CoachTopic.secondary(text, besides: topic)
            update(reply.id, SpartanVoice.wrap(knowledge ?? CoachFAQ.answer(topic, context, question: text),
                                               topic: topic, learned: learned,
                                               also: second.map { ($0, CoachFAQ.answer($0, context, question: text)) },
                                               // A celebration already opens with one.
                                               opener: topic != .brag, question: text))
        }
    }

    /// Spartan's first message of the day, when the user hasn't heard from
    /// him yet today.
    func checkInIfNeeded() {
        guard SpartanStyle.saved != nil, !isResponding else { return }
        let cal = Calendar.current
        if messages.contains(where: { $0.role == .coach && cal.isDateInToday($0.date) }) { return }
        messages.append(ChatMessage(role: .coach, text: SpartanVoice.dailyCheckIn()))
        followUps = SpartanVoice.followUps(after: nil)
        save()
    }

    func clear() {
        followUps = []
        messages = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { onDevice.reset() }
        #endif
        save()
    }

    private func update(_ id: UUID, _ text: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].text = text
    }

    private func save() {
        // Conversation stays on the phone; keep the recent part only.
        let recent = Array(messages.filter { !$0.text.isEmpty }.suffix(60))
        if let data = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(data, forKey: key) }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var onDevice: OnDeviceCoach {
        if let e = engine as? OnDeviceCoach { return e }
        let e = OnDeviceCoach()
        engine = e
        return e
    }
    #endif
}

// MARK: - Apple Intelligence

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct CoachReply {
    @Guide(description: "true only if the question is about fitness, exercise, sports training, nutrition, food, body weight, sleep, recovery or motivation to train; false for anything else, such as football or sports results, news, politics, celebrities, homework or general knowledge")
    var onTopic: Bool
    @Guide(description: "Your answer to the user, at most 5 short sentences")
    var answer: String
}

@available(iOS 26.0, *)
@MainActor
private final class OnDeviceCoach {
    private var session: LanguageModelSession?

    func prewarm() { makeSession(history: []).prewarm() }
    func reset() { session = nil }

    /// Streams the answer through `partial`. Returns false when the model
    /// couldn't answer, so the caller can fall back to the basic answers.
    func reply(to text: String, history: [ChatMessage], partial: @escaping (String) -> Void) async -> Bool {
        let s = session ?? makeSession(history: history)
        session = s
        // Today's intake changes during the day, so it goes with the question
        // rather than into the session — and only when the question is about
        // food. The small model drops rules from the instructions when a
        // question names brands, so the key ones ride along every time.
        func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        var prompt = "[\(L("chat.ctx.reminder"))]\n"
        if CoachTopic.isAboutFood(text) { prompt += "[\(CoachContext.current().todayLine)]\n" }
        prompt += "\n\(L("chat.ctx.question")) \(text)"
        do {
            try await stream(s, prompt, partial)
            return true
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                // Long conversation: start over, carrying the last exchanges.
                session = makeSession(history: Array(history.suffix(4)))
                return await retry(text, partial)
            case .guardrailViolation, .refusal:
                partial(String(localized: "chat.error.refused"))
                return true
            default:
                Self.log.error("guided reply failed: \(String(describing: error), privacy: .public)")
                return await plainRetry(text, history: history, partial)
            }
        } catch {
            Self.log.error("guided reply failed: \(String(describing: error), privacy: .public)")
            return await plainRetry(text, history: history, partial)
        }
    }

    private static let log = Logger(subsystem: "com.oswaldo.powerpump", category: "coach-chat")

    /// Takes out the marks that make text read as machine-written: long
    /// dashes between clauses, "---" divider lines and markdown headings.
    /// Testers spotted them straight away and trusted the answers less.
    /// Stock phrases that give a chatbot away; a coach doesn't talk like that.
    private static let stockPhrases: [NSRegularExpression] = [
        #"^\s*[¡!]?(claro|por supuesto|excelente pregunta|buena pregunta|gran pregunta|certainly|of course|sure|great question|absolutely|bien s[uû]r|excellente question|bonne question|certo|certamente|ottima domanda|bella domanda|com certeza|[oó]tima pergunta|boa pergunta)\s*[!,.:]\s*"#,
        #"\s*(espero que (esto |esta informaci[oó]n )?te (sirva|ayude)|i hope (this|that) helps|hope this helps|j'esp[eè]re que ([cç]a|cela) (t'aide|t'aidera)|spero (che )?(questo )?ti (sia utile|aiuti)|espero (que isso |ter )?(te )?ajud(e|ado))[^.!?\n]*[.!]?\s*$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func humanize(_ text: String) -> String {
        var text = text
        for re in stockPhrases {
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // "claro, aquí tienes…" → "Aquí tienes…"
        if let first = text.first, first.isLowercase { text = first.uppercased() + text.dropFirst() }
        var lines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            var line = raw
            let bare = line.trimmingCharacters(in: .whitespaces)
            if !bare.isEmpty, bare.allSatisfy({ "-—–_*=".contains($0) }) { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.replacingOccurrences(of: " — ", with: ", ")
                .replacingOccurrences(of: " – ", with: ", ")
                .replacingOccurrences(of: "—", with: ", ")
                .replacingOccurrences(of: "–", with: "-")
            lines.append(line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line)
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    /// Second try on a fresh session, as plain text. The structured answer
    /// (on-topic flag + text) is the step most likely to trip the small model;
    /// failing over straight to the basic answers made a capable iPhone reply
    /// "I didn't understand".
    private func plainRetry(_ text: String, history: [ChatMessage],
                            _ partial: @escaping (String) -> Void) async -> Bool {
        let fresh = makeSession(history: Array(history.suffix(4)))
        session = fresh
        func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        let prompt = "[\(L("chat.ctx.reminder"))]\n\n\(L("chat.ctx.question")) \(text)"
        do {
            for try await snapshot in fresh.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.4)) {
                partial(Self.humanize(snapshot.content))
            }
            return true
        } catch {
            Self.log.error("plain reply failed: \(String(describing: error), privacy: .public)")
            session = nil
            return false
        }
    }

    private func retry(_ text: String, _ partial: @escaping (String) -> Void) async -> Bool {
        guard let s = session else { return false }
        do { try await stream(s, text, partial); return true } catch { session = nil; return false }
    }

    /// The model says whether the question is about fitness before it
    /// answers. Told to stay on topic, it still answered general-knowledge
    /// questions with made-up facts — but it classifies them correctly, so
    /// an off-topic answer is swapped for our own reply.
    private func stream(_ s: LanguageModelSession, _ prompt: String, _ partial: @escaping (String) -> Void) async throws {
        var offTopic = false
        for try await snapshot in s.streamResponse(to: prompt, generating: CoachReply.self,
                                                   options: GenerationOptions(temperature: 0.4)) {
            guard let onTopic = snapshot.content.onTopic else { continue }
            if !onTopic { offTopic = true; continue }
            if let answer = snapshot.content.answer { partial(Self.humanize(answer)) }
        }
        if offTopic { partial(String(localized: "chat.error.offTopic")) }
    }

    private func makeSession(history: [ChatMessage]) -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions(CoachContext.current(), history: history))
    }

    /// Written in the phone's language: the on-device model is small, and
    /// English instructions made it mix English words into its answers.
    static func instructions(_ c: CoachContext, history: [ChatMessage]) -> String {
        func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        let style = SpartanStyle.current
        var s = L("spartan.persona") + " " + L("spartan.persona.\(style.rawValue)") + "\n\n"
        s += String(format: L("chat.instructions"), locale: .current, c.calorieFloor, c.profileLines)
        let facts = SpartanMemory.shared.facts
        if !facts.isEmpty {
            s += "\n\n" + L("spartan.ctx.memory") + "\n" + facts.map { "- " + $0.text }.joined(separator: "\n")
        }
        let data = SpartanInsights.all
        if !data.isEmpty {
            s += "\n\n" + L("spartan.ctx.data") + "\n" + data.map { "- " + $0 }.joined(separator: "\n")
        }
        let recent = history.suffix(4).filter { !$0.text.isEmpty }
        if !recent.isEmpty {
            s += "\n\n" + NSLocalizedString("chat.ctx.recent", comment: "") + "\n" + recent.map {
                ($0.role == .user ? "> " : "< ") + String($0.text.prefix(300))
            }.joined(separator: "\n")
        }
        return s
    }
}
#endif

// MARK: - What the coach knows about the user

@MainActor
struct CoachContext {
    var name: String
    var goal: FitnessGoal
    var weightKg: Double
    var proteinTarget: Int
    var kcalTarget: Int
    var calorieFloor: Int
    var eatenKcal: Int
    var eatenProtein: Int
    var todayPlan: DayPlan?
    var todayMeals: DayMeals?
    var profileLines: String
    var todayLine: String
    /// The user's first sport, for sport-specific basic answers.
    var sportID: String?

    static func current() -> CoachContext {
        let p = UserProfile.shared
        let plans = PlanStore.shared
        let food = FoodLogStore.shared
        let target = plans.todayTargets(for: p)
        let floor = p.sex == .female ? 1200 : 1500

        func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        func F(_ k: String, _ args: CVarArg...) -> String { String(format: L(k), locale: .current, arguments: args) }
        func kg(_ v: Double) -> String { String(format: "%.1f", locale: .current, v) }

        let sports = p.practicedSportIDs.compactMap { SportLibrary.byID($0) }.map { L($0.nameKey) }
        let weekdays = p.sportWeekdays.sorted().map { Calendar.current.weekdaySymbols[($0 - 1) % 7] }
        var lines = [
            F("chat.ctx.person", p.name.isEmpty ? "-" : p.name, L(p.sex.rawValue), p.age, Int(p.heightCm),
              kg(p.weightKg), kg(p.targetWeightKg)),
            F("chat.ctx.goal", L(p.goal.rawValue), L(p.activityLevel.rawValue)),
            F("chat.ctx.targets", target.kcal, target.protein, target.carbs, target.fat),
        ]
        if !sports.isEmpty { lines.append(F("chat.ctx.sports", sports.joined(separator: ", "))) }
        if !weekdays.isEmpty { lines.append(F("chat.ctx.sportDays", weekdays.joined(separator: ", "))) }
        let notes = plans.extraContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append(F("chat.ctx.notes", String(notes.prefix(200)))) }
        if let day = plans.todayPlan {
            if day.isSportDay, let sport = day.sport.flatMap(SportLibrary.byID) {
                lines.append(F("chat.ctx.todaySport", L(sport.nameKey)))
            } else if day.isWorkout {
                lines.append(F("chat.ctx.todayWorkout", L(day.focus),
                               day.exercises.prefix(6).map(EXLPlanLine).joined(separator: "; ")))
            } else {
                lines.append(L("chat.ctx.todayRest"))
            }
        }
        if let meals = plans.todayMeals?.meals, !meals.isEmpty {
            lines.append(F("chat.ctx.meals", meals.map { "\(L($0.name)) (\($0.kcal) kcal, \($0.protein) g)" }.joined(separator: "; ")))
        }

        let eatenKcal = Int(food.todayCalories), eatenProtein = Int(food.todayProtein)
        let today = F("chat.ctx.today", eatenKcal, target.kcal, eatenProtein, target.protein)

        return CoachContext(name: p.name, goal: p.goal, weightKg: p.weightKg, proteinTarget: target.protein,
                            kcalTarget: target.kcal, calorieFloor: floor, eatenKcal: eatenKcal,
                            eatenProtein: eatenProtein, todayPlan: plans.todayPlan, todayMeals: plans.todayMeals,
                            profileLines: lines.joined(separator: "\n"), todayLine: today,
                            sportID: p.practicedSportIDs.first)
    }
}

// MARK: - Reviewed answers

/// Our own answers, filled with the user's numbers. Used for the topics the
/// on-device model gets wrong (see CoachTopic.isCurated) and for everything
/// on iPhones without Apple Intelligence.
enum CoachFAQ {
    @MainActor
    static func answer(_ question: String, _ c: CoachContext) -> String {
        answer(CoachTopic.detect(question), c, question: question)
    }

    /// One extra paragraph for the user's sport, so the answer feels like
    /// it comes from a coach who knows them.
    @MainActor
    static func sportTip(_ c: CoachContext, skipping: SportFamily? = nil) -> String {
        guard let id = c.sportID, let sport = SportLibrary.byID(id) else { return "" }
        let family = SportFamily.forSport(id: id)
        if let skipping, family == skipping { return "" }
        let key: String
        switch family {
        case .grappling: key = "chat.faq.sport.grappling"
        case .endurance: key = "chat.faq.sport.endurance"
        case .racquet:   key = "chat.faq.sport.racquet"
        case .team:      key = "chat.faq.sport.team"
        case .water:     key = "chat.faq.sport.water"
        case .mindBody:  key = "chat.faq.sport.mindBody"
        case .power:     key = "chat.faq.sport.power"
        }
        return "\n\n" + String(format: NSLocalizedString(key, comment: ""), locale: .current,
                                NSLocalizedString(sport.nameKey, comment: ""))
    }

    @MainActor
    static func answer(_ topic: CoachTopic?, _ c: CoachContext, question: String = "") -> String {
        func L(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        func F(_ k: String, _ args: CVarArg...) -> String { String(format: L(k), locale: .current, arguments: args) }
        func kg(_ v: Double) -> String { String(format: "%.1f", locale: .current, v) }

        switch topic {
        case .health:        return L("chat.faq.health")
        case .pain:          return L("chat.faq.pain")
        case .loseFast:
            return F("chat.faq.loseFast", kg(c.weightKg * 0.005), kg(c.weightKg * 0.01), c.kcalTarget, c.proteinTarget)
        case .proteinAmount:
            return F("chat.faq.proteinAmount", c.proteinTarget, c.proteinTarget / 4, c.eatenProtein)
        case .proteinChoose: return L("chat.faq.proteinChoose")
        case .creatine:      return L("chat.faq.creatine")
        case .supplements:   return L("chat.faq.supplements")
        case .preWorkout:    return L("chat.faq.preWorkout")
        case .postWorkout:   return F("chat.faq.postWorkout", max(25, Int((c.weightKg * 0.4).rounded())))
        case .loseFat:       return F("chat.faq.loseFat", c.kcalTarget, c.proteinTarget, kg(c.weightKg * 0.0075))
        case .gainMuscle:    return F("chat.faq.gainMuscle", c.kcalTarget, c.proteinTarget)
        case .sleep:         return L("chat.faq.sleep")
        case .water:         return F("chat.faq.water", kg(c.weightKg * 0.035))
        case .plateau:       return L("chat.faq.plateau")
        case .volume:        return L("chat.faq.volume")
        case .recomp:        return F("chat.faq.recomp", c.proteinTarget)
        case .fasting:       return F("chat.faq.fasting", c.kcalTarget, c.proteinTarget)
        case .bellyFat, .lateEating, .cheatMeal, .eatingOut, .alcohol, .cheapFood, .cravings, .snacks, .breakfast,
             .restSets, .repsWeight, .warmUp, .stretching, .trainingDays, .homeWorkout, .beginner, .cardio, .steps,
             .soreness, .scaleWeight, .motivation:
            return L("chat.faq." + topic!.rawValue)
        case .eatToday:
            let head = F("chat.faq.eatToday", c.kcalTarget, c.proteinTarget, c.eatenKcal, c.eatenProtein)
            guard let meals = c.todayMeals?.meals, !meals.isEmpty else { return head + "\n\n" + L("chat.faq.noPlan") }
            let menu = meals.map { "• " + L($0.name) + ": \($0.kcal) kcal · \($0.protein) g" }.joined(separator: "\n")
            return head + "\n\n" + menu
        case .trainToday:
            guard let day = c.todayPlan else { return L("chat.faq.noPlan") }
            if day.isSportDay, let sport = day.sport.flatMap(SportLibrary.byID) {
                return F("chat.faq.sportDay", L(sport.nameKey))
            }
            guard day.isWorkout else { return L("chat.faq.restDay") }
            let list = day.exercises.map { "• " + EXLPlanLine($0) }.joined(separator: "\n")
            return F("chat.faq.trainToday", L(day.focus)) + "\n" + list
        case .strength:
            return F("chat.faq.strength", c.proteinTarget) + sportTip(c)
        case .contactStrength:
            return L("chat.faq.contactStrength") + sportTip(c, skipping: .grappling)
        case .power:         return L("chat.faq.power") + sportTip(c)
        case .endurance:     return L("chat.faq.endurance") + sportTip(c)
        case .generalTraining:
            // Better a useful answer for their sport than "I didn't understand".
            return L("chat.faq.generalTraining") + sportTip(c) + "\n\n" + L("chat.faq.askMore")
        case .crisis:        return L("chat.faq.crisis")
        case .exerciseHowTo, .exerciseSwap, .muscleExercises, .foodInfo:
            // Not in the library: say so, and how to ask again.
            return SpartanKnowledge.answer(topic, question: question) ?? L("chat.faq.\(topic!.rawValue).unknown")
        case .calorieNeeds:  return F("chat.faq.calorieNeeds", c.kcalTarget, c.proteinTarget, c.eatenKcal)
        case .carbs:         return F("chat.faq.carbs", c.kcalTarget)
        case .appHelp:       return SpartanKnowledge.appHelp()
        case .brag:          return SpartanVoice.pick("chat.faq.brag")
        case .trainingTime, .cycle, .teen, .olderAdult, .cramps, .comeback, .failure, .deload, .stress:
            return L("chat.faq." + topic!.rawValue)
        case .shortToday, .easyToday, .moveWorkout, .swapMeal:
            // Normally answered with buttons by SpartanActions; this is the
            // fallback when there's no plan to act on.
            return L("chat.faq.noPlan")
        case nil:
            // Never a dead end: today's menu for a food question, otherwise
            // advice for their sport, and buttons with questions to follow.
            let unsure = SpartanVoice.pick("spartan.unsure.\(SpartanStyle.current.rawValue)") + "\n\n"
            if CoachTopic.isAboutFood(question) { return unsure + answer(.eatToday, c) }
            return unsure + L("chat.faq.generalTraining") + sportTip(c)
        }
    }
}
