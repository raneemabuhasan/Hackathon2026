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

/// Shared user history. Every history mutation persists before publishing UI state.
@MainActor @Observable
final class CycleStore {
    var tab: Tab = .today
    var showLog = false
    var editingLog: DayLog?
    var toast: String?

    var referenceDate = Date()
    var today: Date { Self.cal.startOfDay(for: referenceDate) }
    private(set) var history = PersonalHistory()
    private(set) var storageReady = false
    var storageError: String?
    private var repository: (any HistoryRepository)?
    var starts: [Date] { history.starts.sorted(by: >) }
    var logs: [DayLog] { history.logs }
    var pastLengths: [Int] {
        let dates = starts.reversed()
        return Array(zip(dates, dates.dropFirst()).map { Self.days($0.1, from: $0.0) }.reversed())
    }
    var prediction: PeriodPrediction? {
        CyclePredictionEngine.predict(starts: starts, asOf: .now)
    }
    var reminders: [Reminder] = []
    var grocery: [GroceryItem] = []
    var diets: Set<String> {
        get { history.diets }
        set { commit { $0.diets = newValue } }
    }
    var avoid: Set<String> {
        get { history.avoid }
        set { commit { $0.avoid = newValue } }
    }
    var messages: [ChatMessage] = []

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

    init(repository: (any HistoryRepository)? = nil) {
        do {
            let selected: any HistoryRepository
            if let repository { selected = repository }
            else { selected = try PersonalHistoryRepository.deviceRepository() }
            self.repository = selected
            history = try selected.load()
            storageReady = true
        } catch {
            storageError = "Could not open history. Existing data was preserved. \(error.localizedDescription)"
        }
        messages = [ChatMessage(fromUser: false,
            text: "Your recorded history is available in Cycle. The AI assistant is not connected yet.")]
    }

    @discardableResult
    func commit(_ change: (inout PersonalHistory) -> Void) -> Bool {
        guard storageReady, let repository else {
            storageError = "History is unavailable. Reopen the app to retry; no changes were saved."
            return false
        }
        var next = history
        change(&next)
        do {
            try repository.save(next)
            history = next
            storageError = nil
            return true
        } catch {
            storageError = "Not saved. Please retry. \(error.localizedDescription)"
            return false
        }
    }

    var cycleDay: Int { starts.first.map { Self.days(today, from: $0) + 1 } ?? 0 }
    // TODO(wellness teammate): reviewed personalization independent of inferred biological phase.
    // A neutral selection for browsing the existing meal catalog, never presented as measured phase.
    var currentPhase: Phase { .menstrual }

    func isPeriod(_ date: Date) -> Bool {
        let day = Self.cal.startOfDay(for: date)
        return history.starts.contains { start in
            if let end = history.periodEnds[start] { return day >= start && day <= end }
            return day == start
        } || logs.contains { Self.cal.isDate($0.date, inSameDayAs: day) && $0.flow != "None" }
    }
    func isPredicted(_ date: Date) -> Bool {
        guard let prediction, prediction.windowEnd >= today else { return false }
        return date >= prediction.windowStart && date <= prediction.windowEnd
    }
    func isMaybe(_ date: Date) -> Bool { false }

    @discardableResult
    func savePeriod(start: Date, end: Date?, replacing original: Date? = nil) -> Bool {
        let start = Self.cal.startOfDay(for: start)
        let end = end.map { Self.cal.startOfDay(for: $0) }
        guard start <= today, end.map({ $0 >= start && $0 <= today }) ?? true else {
            storageError = "Check period dates: end must be on or after start, and dates cannot be in the future."
            return false
        }
        let others = history.starts.filter { $0 != original }
        guard !others.contains(start), !others.contains(where: { other in
            let otherEnd = history.periodEnds[other] ?? other
            return start <= otherEnd && (end ?? start) >= other
        }) else {
            storageError = "This period overlaps an existing period. Edit that record instead."
            return false
        }
        return commit { data in
            if let original {
                data.starts.removeAll { $0 == original }
                data.periodEnds.removeValue(forKey: original)
            }
            data.starts.append(start)
            data.periodEnds[start] = end
        }
    }

    func deletePeriod(start: Date) {
        commit {
            $0.starts.removeAll { $0 == start }
            $0.periodEnds.removeValue(forKey: start)
        }
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

    @discardableResult
    func save(_ log: DayLog) -> Bool {
        guard Self.cal.startOfDay(for: log.date) <= today,
              log.pain.map({ (0...10).contains($0) }) ?? true else {
            storageError = "Check the entry date and pain rating."
            return false
        }
        if commit({ $0.save(log) }) {
            showLog = false
            showToast("Entry saved")
            return true
        }
        return false
    }

    var comparisonCycles: [ComparedCycle] {
        SymptomComparisonEngine.cycles(starts: starts, logs: logs, asOf: .now)
    }

    @discardableResult
    func updateLog(_ log: DayLog) -> Bool { save(log) }

    @discardableResult
    func deleteLog(id: UUID) -> Bool { commit { $0.logs.removeAll { $0.id == id } } }

    func deleteAllData() {
        if commit({ $0 = PersonalHistory() }) {
            grocery = []
            reminders = []
            messages = []
            showToast("Your history was deleted")
        }
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

    // MARK: Companion integration pending
    // TODO(AI teammate): inject agent service; expose comparisonCycles and
    // SymptomComparisonEngine.compare as read tools. Save only validated user-confirmed logs.
    // TODO(reminder teammate): persist opt-in reminders and schedule native notifications.
    func label(for action: ChatAction) -> String {
        switch action {
        case .setReminder: return "Reminders unavailable"
        case .notNow: return "Not now"
        case .logCramps: return "Open log"
        case .seeMeals: return "Browse meals"
        }
    }
    func send(_ text: String) {
        messages.append(ChatMessage(fromUser: true, text: text))
        messages.append(ChatMessage(fromUser: false,
            text: "AI assistant is not connected yet. Use + to record symptoms or Cycle to review comparisons."))
    }
    func perform(_ action: ChatAction, from messageID: UUID) {
        switch action {
        case .logCramps: showLog = true
        case .seeMeals: tab = .nourish
        case .setReminder, .notNow: break
        }
    }
}
