import Foundation
import FirebaseAI

/// Petal's companion, backed by Gemini through Firebase AI Logic (Vertex AI backend).
///
/// The model never touches Firestore itself. It asks for one of the tools below, the app runs the
/// tool against the signed-in user's data (so Firestore rules still apply), and the result goes back
/// to the model. Keep all model access in this class so it can later move behind a Cloud Function
/// (e.g. to enforce a paywall) without touching the rest of the app.
@MainActor
final class Assistant {
    /// Most current Gemini models aren't served from us-central1 (the SDK's default location).
    static let location = "global"
    /// Gemini 3.x models require "thought signatures" to be sent back with tool results, which the
    /// Firebase 11.x SDK (pinned for Xcode 15.4) doesn't support, so every tool call would fail with a 400.
    /// Gemini 2.5 Flash doesn't require them. Once the team is on Xcode 16.3+, upgrade Firebase to 12.x
    /// and switch this to a current model (e.g. gemini-3.8-flash).
    static let modelName = "gemini-2.5-flash"

    private weak var store: CycleStore?
    private let chat: Chat

    init(store: CycleStore) {
        self.store = store
        let model = FirebaseAI.firebaseAI(backend: .vertexAI(location: Self.location)).generativeModel(
            modelName: Self.modelName,
            tools: [.functionDeclarations(Self.tools)],
            systemInstruction: ModelContent(role: "system", parts: Self.instructions(for: store))
        )
        chat = model.startChat()
    }

    func reply(to text: String) async throws -> String {
        var response = try await chat.sendMessage(text)
        // The model may chain a few tool calls (e.g. read history, then log); cap it to avoid loops.
        for _ in 0..<4 {
            let calls = response.functionCalls
            guard !calls.isEmpty else { break }
            var results: [FunctionResponsePart] = []
            for call in calls {
                results.append(FunctionResponsePart(name: call.name, response: await run(call)))
            }
            response = try await chat.sendMessage([ModelContent(role: "function", parts: results)])
        }
        return response.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Sorry, I couldn't come up with an answer. Could you say that another way?"
    }

    // MARK: Prompt

    private static func instructions(for store: CycleStore) -> String {
        let today = store.today.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        return """
        You are the wellness companion inside Petal, a period-tracking app. Today is \(today) \
        (\(dayFormatter.string(from: store.today))) in the user's time zone, \(TimeZone.current.identifier). \
        The user's name is \(store.name).

        What the app currently estimates: cycle day \(store.cycleDay) of about \(store.average), \
        \(store.currentPhase.name.lowercased()) phase, next period likely between \
        \(dayFormatter.string(from: store.windowStart)) and \(dayFormatter.string(from: store.windowEnd)).

        Rules:
        - You are not a doctor. Don't diagnose, and don't claim that foods, supplements or habits treat \
        symptoms or balance hormones. For severe pain, very heavy bleeding, fainting or anything worrying, \
        suggest contacting a GP or doctor (or NHS 111 in the UK); in an emergency, urgent care.
        - Answer questions about the user's past only from get_logs or get_cycle_summary. Never guess or \
        invent past entries. If nothing is logged, say so.
        - Only save what the user asks you to record, using log_day. Turn relative dates ("yesterday", \
        "on Monday") into YYYY-MM-DD using today's date. Never log future dates.
        - Put the user's own words about strength or detail (e.g. "strong") in description. You may ask \
        for a 0-10 pain rating, but never make one up; leave out anything the user didn't say.
        - Only say something was saved after the tool returns ok: true. Confirm with the date, the \
        symptoms and the severity they described. If a tool returns an error, say it wasn't saved.
        - Only create reminders the user asked for, using add_reminder.
        - Predictions are an estimated window, not a date, and not for contraception or fertility planning.
        - Keep replies warm and short: 1-3 sentences unless asked for more. Plain text, no markdown.
        """
    }

    // MARK: Tools

    private static let tools: [FunctionDeclaration] = [
        FunctionDeclaration(
            name: "log_day",
            description: "Save symptoms, moods, flow, pain or details for one day. Adds to anything already logged that day.",
            parameters: [
                "date": .string(description: "Day as YYYY-MM-DD in the user's local time. Use today if the user didn't say."),
                "symptoms": .array(items: .enumeration(values: CycleStore.symptomOptions), description: "Symptoms to add."),
                "moods": .array(items: .enumeration(values: CycleStore.moodOptions), description: "Moods to add."),
                "flow": .enumeration(values: ["None", "Light", "Medium", "Heavy"], description: "Bleeding that day."),
                "pain": .integer(description: "Pain from 0 to 10. Only if the user gave a number."),
                "description": .string(description: "The user's own words about severity or details, e.g. \"strong\"."),
            ],
            optionalParameters: ["symptoms", "moods", "flow", "pain", "description"]
        ),
        FunctionDeclaration(
            name: "get_logs",
            description: "Read the user's saved day logs between two dates, inclusive (at most 120 days).",
            parameters: [
                "from": .string(description: "First day, YYYY-MM-DD."),
                "to": .string(description: "Last day, YYYY-MM-DD."),
            ]
        ),
        FunctionDeclaration(
            name: "get_cycle_summary",
            description: "Cycle day, phase, predicted next-period window, recent cycle lengths and the most common logged symptoms.",
            parameters: ["days": .integer(description: "How many days back to count symptoms. Defaults to 60.")],
            optionalParameters: ["days"]
        ),
        FunctionDeclaration(
            name: "add_reminder",
            description: "Create a reminder the user asked for. It becomes a phone notification.",
            parameters: [
                "title": .string(description: "What to remind them about, e.g. \"Restock pads\"."),
                "schedule": .enumeration(values: ["daily", "once", "before_period"],
                                         description: "daily = every day; once = on one date; before_period = some days before the predicted period window."),
                "time": .string(description: "24-hour HH:mm. Default 09:00 if the user didn't say."),
                "date": .string(description: "YYYY-MM-DD, only for schedule once."),
                "days_before": .integer(description: "1-7, only for schedule before_period. Default 2."),
            ],
            optionalParameters: ["time", "date", "days_before"]
        ),
        FunctionDeclaration(
            name: "get_meal_ideas",
            description: "Meal ideas for a cycle phase, already filtered by the user's diet and allergen preferences.",
            parameters: ["phase": .enumeration(values: Phase.allCases.map(\.rawValue), description: "Defaults to the current phase.")],
            optionalParameters: ["phase"]
        ),
    ]

    private func run(_ call: FunctionCallPart) async -> JSONObject {
        guard let store else { return Self.failure("The app isn't ready yet.") }
        let args = call.args
        switch call.name {
        case "log_day": return await logDay(args, store)
        case "get_logs": return getLogs(args, store)
        case "get_cycle_summary": return cycleSummary(args, store)
        case "add_reminder": return await addReminder(args, store)
        case "get_meal_ideas": return mealIdeas(args, store)
        default: return Self.failure("Unknown tool \(call.name).")
        }
    }

    private func logDay(_ args: JSONObject, _ store: CycleStore) async -> JSONObject {
        let date: Date
        if let text = args.string("date") {
            guard let parsed = Self.day(text) else { return Self.failure("Date must be YYYY-MM-DD.") }
            date = parsed
        } else {
            date = store.today
        }
        guard date <= store.today else { return Self.failure("Can't log a future date.") }
        guard date >= CycleStore.add(store.today, -365) else { return Self.failure("Can only log the past year.") }

        let symptoms = args.strings("symptoms"), moods = args.strings("moods")
        let unknown = symptoms.filter { !CycleStore.symptomOptions.contains($0) } + moods.filter { !CycleStore.moodOptions.contains($0) }
        guard unknown.isEmpty else { return Self.failure("Unknown symptom or mood: \(unknown.joined(separator: ", ")).") }
        let flow = args.string("flow")
        if let flow, !["None", "Light", "Medium", "Heavy"].contains(flow) { return Self.failure("Flow must be None, Light, Medium or Heavy.") }
        let pain = args.int("pain")
        if let pain, !(0...10).contains(pain) { return Self.failure("Pain must be between 0 and 10.") }
        let description = args.string("description")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symptoms.isEmpty || !moods.isEmpty || flow != nil || pain != nil || !(description ?? "").isEmpty else {
            return Self.failure("Nothing to log.")
        }

        var log = store.log(for: date) ?? DayLog(date: CycleStore.cal.startOfDay(for: date))
        log.symptoms += symptoms.filter { !log.symptoms.contains($0) }
        log.moods += moods.filter { !log.moods.contains($0) }
        if let flow { log.flow = flow }
        if let pain { log.pain = pain }
        if let description, !description.isEmpty {
            let line = symptoms.isEmpty ? description : "\(symptoms.joined(separator: ", ")): \(description)"
            log.note = log.note.isEmpty ? line : log.note + "\n" + line
        }

        do {
            try await store.write(log)
            return ["ok": .bool(true), "saved": .object(Self.json(log))]
        } catch {
            return Self.failure("Saving failed: \(error.localizedDescription)")
        }
    }

    private func getLogs(_ args: JSONObject, _ store: CycleStore) -> JSONObject {
        let to = args.string("to").flatMap(Self.day) ?? store.today
        let from = args.string("from").flatMap(Self.day) ?? CycleStore.add(to, -30)
        guard from <= to else { return Self.failure("from must be on or before to.") }
        guard CycleStore.days(to, from: from) <= 120 else { return Self.failure("Ask for at most 120 days at a time.") }
        let logs = store.logs
            .filter { $0.date >= from && $0.date < CycleStore.add(to, 1) }
            .sorted { $0.date < $1.date }
        return ["ok": .bool(true), "count": .number(Double(logs.count)), "logs": .array(logs.map { .object(Self.json($0)) })]
    }

    private func cycleSummary(_ args: JSONObject, _ store: CycleStore) -> JSONObject {
        let days = min(max(args.int("days") ?? 60, 1), 365)
        let since = CycleStore.add(store.today, -days)
        var counts: [String: Int] = [:]
        for log in store.logs where log.date >= since { for s in log.symptoms { counts[s, default: 0] += 1 } }
        let top = counts.sorted { $0.value > $1.value }.prefix(5)
        return [
            "ok": .bool(true),
            "cycleDay": .number(Double(store.cycleDay)),
            "phase": .string(store.currentPhase.name),
            "lastPeriodStart": .string(Self.dayFormatter.string(from: store.lastStart)),
            "nextPeriodWindow": .object([
                "from": .string(Self.dayFormatter.string(from: store.windowStart)),
                "to": .string(Self.dayFormatter.string(from: store.windowEnd)),
            ]),
            "averageCycleLength": .number(Double(store.average)),
            "recentCycleLengths": .array(store.completedCycles.map { .number(Double($0.length)) }),
            "topSymptoms": .array(top.map { .object(["symptom": .string($0.key), "days": .number(Double($0.value))]) }),
            "symptomWindowDays": .number(Double(days)),
        ]
    }

    private func addReminder(_ args: JSONObject, _ store: CycleStore) async -> JSONObject {
        guard let title = args.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 80 else {
            return Self.failure("A reminder needs a title of up to 80 characters.")
        }
        let kind: Reminder.Kind
        switch args.string("schedule") {
        case "daily": kind = .daily
        case "once": kind = .once
        case "before_period": kind = .beforePeriod
        default: return Self.failure("schedule must be daily, once or before_period.")
        }
        var hour = 9, minute = 0
        if let time = args.string("time") {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return Self.failure("time must be HH:mm.") }
            (hour, minute) = (parts[0], parts[1])
        }
        var reminder = Reminder(title: title, kind: kind, hour: hour, minute: minute)
        switch kind {
        case .daily:
            break
        case .once:
            guard let date = args.string("date").flatMap(Self.day), date >= store.today else {
                return Self.failure("A one-off reminder needs a date (YYYY-MM-DD) today or later.")
            }
            reminder.date = date
        case .beforePeriod:
            let days = args.int("days_before") ?? 2
            guard (1...7).contains(days) else { return Self.failure("days_before must be 1-7.") }
            reminder.daysBefore = days
        }
        do {
            try await store.addReminder(reminder)
            return ["ok": .bool(true), "title": .string(title), "when": .string(reminder.detail(windowStart: store.windowStart))]
        } catch {
            return Self.failure("Saving failed: \(error.localizedDescription)")
        }
    }

    private func mealIdeas(_ args: JSONObject, _ store: CycleStore) -> JSONObject {
        let phase = args.string("phase").flatMap(Phase.init(rawValue:)) ?? store.currentPhase
        let meals = store.shownMeals(for: phase).map {
            JSONValue.object(["name": .string($0.name), "why": .string($0.why), "ingredients": .array($0.items.map(JSONValue.string))])
        }
        return ["ok": .bool(true), "phase": .string(phase.name), "meals": .array(meals)]
    }

    // MARK: Meal ideas (Nourish)

    /// Asks Gemini for recipes that suit a cycle phase and the user's diet. Callers should still
    /// re-check allergens: the model's own labels can be wrong.
    static func mealIdeas(for phase: Phase, diets: Set<String>, avoid: Set<String>, notLike previous: [String] = []) async throws -> [Meal] {
        let model = FirebaseAI.firebaseAI(backend: .vertexAI(location: location)).generativeModel(
            modelName: modelName,
            // Thinking off: same quality for recipes, ~8 s instead of 20-60 s.
            generationConfig: GenerationConfig(temperature: 0.9, responseMIMEType: "application/json", responseSchema: mealSchema,
                                               thinkingConfig: ThinkingConfig(thinkingBudget: 0))
        )
        let prompt = """
        Suggest 4 different recipes for someone in the \(phase.name.lowercased()) phase of their menstrual cycle. \
        Context: \(phase.blurb)

        Requirements:
        - Every recipe must suit: \(diets.isEmpty ? "no particular diet" : diets.sorted().joined(separator: ", ")).
        - Must not contain, even as part of another ingredient: \(avoid.isEmpty ? "nothing excluded" : avoid.sorted().joined(separator: ", ")). \
        For example nuts rules out almond milk and pesto; gluten rules out regular pasta, bread and soy sauce.
        - One breakfast, one lunch, one dinner and one snack. Each under 45 minutes with common supermarket ingredients.
        - why: one friendly sentence on why it fits this phase, in general nutrition terms (iron, fibre, protein, \
        hydration, warmth). Never claim food treats symptoms, cures anything or balances hormones.
        - diets: every listed diet the recipe fits. allergens: every listed allergen it contains. Be thorough.
        - ingredients: with metric quantities, e.g. "200 g red lentils". shopping: 3-6 plain item names for a \
        grocery list, e.g. "Red lentils". steps: 3-6 short steps.
        \(previous.isEmpty ? "" : "- Don't repeat these: \(previous.joined(separator: ", ")).")
        """
        let response = try await model.generateContent(prompt)
        guard let data = response.text?.data(using: .utf8) else { throw MealError.empty }
        return try JSONDecoder().decode([GeneratedMeal].self, from: data).map {
            Meal(name: $0.name, why: $0.why, diets: $0.diets, allergens: $0.allergens, items: $0.shopping,
                 minutes: $0.minutes, servings: $0.servings, ingredients: $0.ingredients, steps: $0.steps)
        }
    }

    private enum MealError: Error { case empty }

    private struct GeneratedMeal: Decodable {
        let name, why: String
        let minutes, servings: Int
        let diets, allergens, ingredients, shopping, steps: [String]
    }

    private static let mealSchema = Schema.array(items: .object(properties: [
        "name": .string(),
        "why": .string(),
        "minutes": .integer(description: "Total time in minutes."),
        "servings": .integer(),
        "diets": .array(items: .enumeration(values: CycleStore.dietOptions)),
        "allergens": .array(items: .enumeration(values: CycleStore.allergenOptions)),
        "ingredients": .array(items: .string()),
        "shopping": .array(items: .string()),
        "steps": .array(items: .string()),
    ]))

    // MARK: Helpers

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = CycleStore.cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func day(_ text: String) -> Date? { dayFormatter.date(from: text).map(CycleStore.cal.startOfDay) }

    private static func failure(_ message: String) -> JSONObject { ["ok": .bool(false), "error": .string(message)] }

    private static func json(_ log: DayLog) -> JSONObject {
        [
            "date": .string(dayFormatter.string(from: log.date)),
            "flow": .string(log.flow),
            "symptoms": .array(log.symptoms.map(JSONValue.string)),
            "moods": .array(log.moods.map(JSONValue.string)),
            "pain": .number(Double(log.pain)),
            "energy": .number(Double(log.energy)),
            "note": .string(log.note),
        ]
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        if case let .string(value)? = self[key] { return value }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case let .number(value)? = self[key] { return Int(value) }
        return nil
    }

    func strings(_ key: String) -> [String] {
        guard case let .array(values)? = self[key] else { return [] }
        return values.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
    }
}
