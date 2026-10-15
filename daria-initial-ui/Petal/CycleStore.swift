import SwiftUI
import Observation

enum Tab { case today, cycle, nourish, companion }

enum Phase: String, CaseIterable, Identifiable {
    case menstrual, follicular, mid, luteal
    var id: String { rawValue }

    var name: String {
        switch self {
        case .menstrual: "Period"
        case .follicular: "Follicular"
        case .mid: "Mid-cycle"
        case .luteal: "Luteal"
        }
    }

    var color: Color {
        switch self {
        case .menstrual: Palette.rose
        case .follicular: Palette.blush
        case .mid: Palette.pink
        case .luteal: Palette.berry
        }
    }

    var artColors: [Color] {
        switch self {
        case .menstrual: [Palette.rose, Palette.pink]
        case .follicular: [Palette.blush, Palette.mist]
        case .mid: [Palette.pink, Palette.blush]
        case .luteal: [Palette.berry, Palette.petal]
        }
    }

    var blurb: String {
        switch self {
        case .menstrual: "Iron-rich foods, warm meals and plenty of fluids are good general choices while you bleed. Rest counts too."
        case .follicular: "Many people feel lighter and more energetic now. Fresh, colourful meals with protein and fibre keep you going."
        case .mid: "A good time for whatever feels good: balanced plates, lots of veg, and staying hydrated if you're active."
        case .luteal: "Cravings and lower energy are common before a period. Regular meals with slow-release carbs can help you feel steadier."
        }
    }
}

struct DayLog: Identifiable {
    let id = UUID()
    var date: Date
    var flow = "None"
    var moods: [String] = []
    var symptoms: [String] = []
    var pain = 0
    var energy = 3
    var note = ""
}

struct Meal: Identifiable {
    let id = UUID()
    let name: String
    let why: String
    let diets: [String]
    let allergens: [String]
    let items: [String]
}

struct Reminder: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var on: Bool
}

struct GroceryItem: Identifiable {
    let id = UUID()
    var name: String
    var done = false
}

enum ChatAction: Hashable {
    case setReminder(String)
    case notNow
    case logCramps
    case seeMeals
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
    var note: String? = nil
    var link: URL? = nil
    var actions: [ChatAction] = []
}

/// All app state for the mockup. Everything here is fictional demo data held in memory.
@MainActor @Observable
final class CycleStore {
    private(set) var periodHistory = PeriodHistory()
    var periodStorageError: String?
    private let periodKey = "petal.periodHistory.v1"

    func savePeriod(id: UUID? = nil, start: Date, end: Date?) throws {
        var next = periodHistory
        try next.save(id: id, start: start, end: end)
        try persistPeriods(next)
    }

    func removePeriod(id: UUID) throws {
        var next = periodHistory
        next.remove(id: id)
        try persistPeriods(next)
    }

    private func persistPeriods(_ next: PeriodHistory) throws {
        let data = try JSONEncoder().encode(next)
        UserDefaults.standard.set(data, forKey: periodKey)
        periodHistory = next
        periodStorageError = nil
    }

    private(set) var baseline: CycleBaseline?
    var showCycleSetup = false
    var forecast: CycleForecast { CycleForecast(baseline: baseline, records: periodHistory.records) }
    var ongoingPeriod: PeriodRecord? { periodHistory.records.first { $0.end == nil } }
    var forecastBasis: String {
        if forecast.sampleCount > 0 { return "Based on \(forecast.sampleCount) recorded cycle intervals." }
        return baseline?.cycleDays == nil ? "Using a 28-day starting estimate while we learn your cycle." : "Based on the cycle length you entered."
    }
    func saveBaseline(_ value: CycleBaseline, ongoing: Bool) throws {
        let data = try JSONEncoder().encode(value)
        if ongoing, let start = value.lastStart, ongoingPeriod == nil {
            try savePeriod(start: start, end: nil)
        }
        UserDefaults.standard.set(data, forKey: "petal.cycleBaseline.v1")
        baseline = value
        showCycleSetup = false
    }

    var tab: Tab = .today
    var showLog = false
    var toast: String?

    var today: Date
    let periodLength = 5
    let pastLengths = CycleStore.demoLengths
    let starts: [Date]

    var logs: [DayLog] = []
    var reminders: [Reminder] = []
    var grocery: [GroceryItem] = [GroceryItem(name: "Oat milk"), GroceryItem(name: "Ginger tea", done: true)]
    var diets: Set<String> = ["vegetarian"]
    var avoid: Set<String> = ["nuts"]
    var messages: [ChatMessage] = []

    static let demoLengths = [28, 31, 27, 29, 30] // most recent completed cycle first
    static let cal = Calendar.current
    static func add(_ date: Date, _ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: date)! }
    static func days(_ a: Date, from b: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: b), to: cal.startOfDay(for: a)).day ?? 0
    }

    static let symptomOptions = ["Cramps", "Headache", "Bloating", "Tender breasts", "Back pain", "Acne", "Fatigue", "Cravings", "Trouble sleeping"]
    static let moodOptions = ["Calm", "Happy", "Confident", "Tired", "Anxious", "Irritable", "Low", "Sensitive"]
    static let dietOptions = ["vegetarian", "vegan", "gluten-free", "dairy-free"]
    static let allergenOptions = ["nuts", "dairy", "gluten", "soy", "eggs", "fish", "sesame"]
    static let nhsPeriodPain = URL(string: "https://www.nhs.uk/conditions/period-pain/")!
    static let nhsHeavyPeriods = URL(string: "https://www.nhs.uk/conditions/heavy-periods/")!

    init() {
        let t = Self.cal.startOfDay(for: .now)
        today = t
        if let data = UserDefaults.standard.data(forKey: "petal.cycleBaseline.v1") {
            baseline = try? JSONDecoder().decode(CycleBaseline.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: periodKey) {
            do { periodHistory = try JSONDecoder().decode(PeriodHistory.self, from: data) }
            catch { periodStorageError = "Saved period records could not be read. Your stored data has not been overwritten." }
        }
        var s = [Self.add(t, -13)]
        for length in Self.demoLengths { s.append(Self.add(s.last!, -length)) }
        starts = s
        showCycleSetup = baseline == nil

        for start in s.prefix(3) {
            logs += [
                DayLog(date: start, flow: "Heavy", symptoms: ["Cramps", "Fatigue"]),
                DayLog(date: Self.add(start, 1), flow: "Medium", symptoms: ["Cramps", "Back pain"]),
                DayLog(date: Self.add(start, 2), flow: "Light", symptoms: ["Fatigue"]),
                DayLog(date: Self.add(start, -2), symptoms: ["Bloating", "Cravings"]),
                DayLog(date: Self.add(start, -4), symptoms: ["Tender breasts", "Trouble sleeping"]),
            ]
        }
        logs.append(DayLog(date: Self.add(t, -6), symptoms: ["Headache"]))

        reminders = [
            Reminder(title: "Pack your period kit", detail: "\(fmt(Self.add(windowStart, -1))) · the day before your window", on: true),
            Reminder(title: "Evening check-in", detail: "Every day · 8:30 pm", on: true),
            Reminder(title: "Restock pads & tampons", detail: "\(fmt(Self.add(windowStart, -4))) · once", on: false),
        ]
        messages = [ChatMessage(
            fromUser: false,
            text: "Hi Maya. You're on day \(cycleDay), in your \(currentPhase.name.lowercased()) phase. Your next period will probably start between \(fmt(windowStart)) and \(fmt(windowEnd)).",
            note: "I'm a wellness companion, not a doctor. I won't diagnose anything.")]
    }

    // MARK: Cycle maths

    var lastStart: Date { starts[0] }
    private var mean: Double { Double(pastLengths.reduce(0, +)) / Double(pastLengths.count) }
    var average: Int { Int(mean.rounded()) }
    /// Uncertainty in days either side of the predicted start, never less than 2.
    var spread: Int {
        let variance = pastLengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(pastLengths.count)
        return max(2, Int((sqrt(variance) * 1.5).rounded()))
    }
    var nextStart: Date { Self.add(lastStart, average) }
    var windowStart: Date { Self.add(nextStart, -spread) }
    var windowEnd: Date { Self.add(nextStart, spread) }
    var cycleDay: Int { Self.days(today, from: lastStart) + 1 }

    func range(of phase: Phase) -> ClosedRange<Int> {
        switch phase {
        case .menstrual: 1...periodLength
        case .follicular: (periodLength + 1)...(average - 16)
        case .mid: (average - 15)...(average - 12)
        case .luteal: (average - 11)...average
        }
    }
    func phase(forDay day: Int) -> Phase { Phase.allCases.first { range(of: $0).contains(day) } ?? .luteal }
    var currentPhase: Phase { phase(forDay: cycleDay) }

    func isPeriod(_ date: Date) -> Bool {
        date <= today && starts.contains { let x = Self.days(date, from: $0); return x >= 0 && x < periodLength }
    }
    func isPredicted(_ date: Date) -> Bool {
        let x = Self.days(date, from: nextStart); return x >= 0 && x < periodLength
    }
    func isMaybe(_ date: Date) -> Bool {
        !isPredicted(date) && date >= windowStart && date <= Self.add(windowEnd, periodLength - 1)
    }

    var symptomCounts: [(name: String, count: Int)] {
        let since = Self.add(today, -60)
        var counts: [String: Int] = [:]
        for log in logs where log.date >= since { for s in log.symptoms { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    func fmt(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }

    // MARK: Actions

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }

    func save(_ log: DayLog) {
        logs.removeAll { Self.cal.isDate($0.date, inSameDayAs: today) }
        logs.append(log)
        showLog = false
        let tags = log.moods.count + log.symptoms.count
        showToast("Saved · \(tags == 0 ? "no" : "\(tags)") tags logged")
    }

    func deleteAllData() {
        logs = []
        grocery = []
        periodHistory = PeriodHistory()
        UserDefaults.standard.removeObject(forKey: periodKey)
        periodStorageError = nil
        showToast("Your data was deleted")
    }

    // MARK: Nourish

    static let meals: [Phase: [Meal]] = [
        .menstrual: [
            Meal(name: "Lentil & spinach dal", why: "Plant iron plus vitamin C from a squeeze of lemon helps absorption.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: [], items: ["Red lentils", "Spinach", "Lemons"]),
            Meal(name: "Salmon, rice & greens", why: "Oily fish is a source of omega-3 fats.", diets: ["gluten-free", "dairy-free"], allergens: ["fish"], items: ["Salmon fillets", "Brown rice", "Broccoli"]),
            Meal(name: "Ginger miso soup", why: "Warm and gentle when you don't feel like cooking.", diets: ["vegetarian", "vegan", "dairy-free"], allergens: ["soy"], items: ["Miso paste", "Fresh ginger", "Tofu"]),
            Meal(name: "Dark chocolate & orange", why: "A small comfort snack. Enjoy it, no guilt.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: [], items: ["Dark chocolate", "Oranges"]),
        ],
        .follicular: [
            Meal(name: "Yogurt bowl with berries & oats", why: "Protein and fibre to start the day.", diets: ["vegetarian"], allergens: ["dairy", "gluten"], items: ["Greek yogurt", "Berries", "Oats"]),
            Meal(name: "Chickpea quinoa salad", why: "Fresh, filling and easy to batch-cook.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: [], items: ["Chickpeas", "Quinoa", "Cucumber"]),
            Meal(name: "Egg & avocado toast", why: "Quick protein and healthy fats.", diets: ["vegetarian", "dairy-free"], allergens: ["eggs", "gluten"], items: ["Eggs", "Avocados", "Sourdough"]),
            Meal(name: "Tofu veggie stir-fry", why: "Lots of veg, ready in 15 minutes.", diets: ["vegetarian", "vegan", "dairy-free"], allergens: ["soy"], items: ["Firm tofu", "Peppers", "Soy sauce"]),
        ],
        .mid: [
            Meal(name: "Rainbow grain bowl", why: "As many colours as you can fit.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: ["sesame"], items: ["Tahini", "Red cabbage", "Carrots"]),
            Meal(name: "Chicken & veg traybake", why: "One tray, minimal washing up.", diets: ["gluten-free", "dairy-free"], allergens: [], items: ["Chicken thighs", "Courgette", "Red onion"]),
            Meal(name: "Berry spinach smoothie", why: "Hydrating and easy on the go.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: [], items: ["Frozen berries", "Spinach", "Bananas"]),
            Meal(name: "Pasta primavera", why: "Wholewheat pasta with spring veg.", diets: ["vegetarian"], allergens: ["gluten", "dairy"], items: ["Wholewheat pasta", "Peas", "Parmesan"]),
        ],
        .luteal: [
            Meal(name: "Sweet potato & black bean chili", why: "Slow-release carbs and fibre.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: [], items: ["Sweet potatoes", "Black beans", "Tomatoes"]),
            Meal(name: "Banana oat porridge with almonds", why: "Warm, steady breakfast.", diets: ["vegetarian", "vegan", "dairy-free"], allergens: ["nuts", "gluten"], items: ["Oats", "Bananas", "Almonds"]),
            Meal(name: "Pumpkin seed & kale salad", why: "Seeds and greens are sources of magnesium.", diets: ["vegetarian", "vegan", "gluten-free", "dairy-free"], allergens: [], items: ["Kale", "Pumpkin seeds", "Lemons"]),
            Meal(name: "Turkey & brown rice bowl", why: "Simple, balanced and filling.", diets: ["gluten-free", "dairy-free"], allergens: [], items: ["Turkey mince", "Brown rice", "Spinach"]),
        ],
    ]

    func meals(for phase: Phase) -> [Meal] {
        (Self.meals[phase] ?? []).filter { meal in
            diets.allSatisfy(meal.diets.contains) && !meal.allergens.contains(where: avoid.contains)
        }
    }

    func isOnList(_ meal: Meal) -> Bool { meal.items.allSatisfy { item in grocery.contains { $0.name == item } } }

    func toggleList(_ meal: Meal) {
        if isOnList(meal) {
            grocery.removeAll { meal.items.contains($0.name) }
            showToast("Removed from grocery list")
        } else {
            for item in meal.items where !grocery.contains(where: { $0.name == item }) {
                grocery.append(GroceryItem(name: item))
            }
            showToast("Added \(meal.items.count) items to your list")
        }
    }

    // MARK: Companion

    func label(for action: ChatAction) -> String {
        switch action {
        case .setReminder: "Set for \(fmt(Self.add(windowStart, -2)))"
        case .notNow: "Not now"
        case .logCramps: "Log cramps today"
        case .seeMeals: "See more ideas"
        }
    }

    func send(_ text: String) {
        messages.append(ChatMessage(fromUser: true, text: text))
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            reply(to: text)
        }
    }

    func perform(_ action: ChatAction, from messageID: UUID) {
        if let i = messages.firstIndex(where: { $0.id == messageID }) { messages[i].actions = [] }
        switch action {
        case .setReminder(let title):
            reminders.insert(Reminder(title: title, detail: "\(fmt(Self.add(windowStart, -2))) · once", on: true), at: 0)
            showToast("Reminder set")
            ai("Done. You'll find it under Reminders, and you can switch it off any time.")
        case .notNow:
            ai("No problem.")
        case .logCramps:
            showLog = true
        case .seeMeals:
            tab = .nourish
        }
    }

    private func ai(_ text: String, note: String? = nil, link: URL? = nil, actions: [ChatAction] = []) {
        messages.append(ChatMessage(fromUser: false, text: text, note: note, link: link, actions: actions))
    }

    private func reply(to question: String) {
        let q = question.lowercased()
        let has = { (words: [String]) in words.contains { q.contains($0) } }

        if has(["faint", "soak", "very heavy", "severe", "unbearable", "clot", "pass out"]) {
            ai("That sounds like something to get checked. Please contact a GP, or call NHS 111 if you're in the UK. If you feel faint or very unwell, seek urgent care.",
               note: "I can't assess symptoms. NHS: heavy periods", link: Self.nhsHeavyPeriods)
        } else if has(["remind"]) {
            var what = question
            if let r = question.range(of: "remind me to ", options: .caseInsensitive) ?? question.range(of: "remind me ", options: .caseInsensitive) {
                what = String(question[r.upperBound...])
            }
            what = what.trimmingCharacters(in: .whitespacesAndNewlines)
            if what.isEmpty || what.lowercased() == question.lowercased() { what = "Check in with yourself" }
            let title = what.prefix(1).uppercased() + what.dropFirst()
            ai("Want me to remind you to \(what.lowercased())? I'd suggest \(fmt(Self.add(windowStart, -2))), two days before your likely window.",
               actions: [.setReminder(title), .notNow])
        } else if has(["cramp", "pain", "hurt"]) {
            ai("Some things people find helpful for period pain: a heat pad on your tummy, a warm bath, gentle exercise like walking or yoga, and over-the-counter pain relief if it's suitable for you (check with a pharmacist).",
               note: "Source: NHS period pain. If pain stops you doing everyday things, talk to a GP.", link: Self.nhsPeriodPain, actions: [.logCramps])
        } else if has(["eat", "food", "hungry", "meal", "craving", "snack"]) {
            let meal = meals(for: currentPhase).first ?? Self.meals[currentPhase]![0]
            ai("You're in your \(currentPhase.name.lowercased()) phase. \(currentPhase.blurb) One idea that fits your preferences: \(meal.name).",
               note: "General nutrition ideas, not treatment.", actions: [.seeMeals])
        } else if has(["tired", "energy", "exhaust", "sleep"]) {
            let n = logs.filter { $0.symptoms.contains("Fatigue") }.count
            ai("You've logged fatigue on \(n) days recently, mostly in the first days of your period. That's a pattern many people notice. Regular meals, water and an earlier night can help. If tiredness is constant or getting worse, a GP can check things like iron levels.")
        } else if has(["when", "next period", "late"]) {
            ai("Your next period is most likely between \(fmt(windowStart)) and \(fmt(windowEnd)). Your cycles have ranged from \(pastLengths.min()!) to \(pastLengths.max()!) days, so I give a window instead of one date.",
               note: "Not for contraception or fertility planning.")
        } else {
            ai("I can help with reminders, food ideas for your cycle, self-care for period pain, or a summary of what you've logged. What would be most useful?")
        }
    }
}
