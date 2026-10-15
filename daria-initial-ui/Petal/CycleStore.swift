import SwiftUI
import Observation
import FirebaseFirestore

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

struct DayLog: Identifiable, Codable {
    var date: Date
    var flow = "None"
    var moods: [String] = []
    var symptoms: [String] = []
    var pain = 0
    var energy = 3
    var note = ""
    /// One log per day, so the day is the Firestore document ID.
    var id: String { CycleStore.key(date) }
}

/// users/{uid} — set during onboarding.
struct Profile: Codable {
    var name: String
    var lastPeriodStart: Date
    var cycleLength: Int
    var periodLength: Int
    var diets: [String] = []
    var avoid: [String] = []
}

struct Meal: Identifiable {
    let id = UUID()
    let name: String
    let why: String
    let diets: [String]
    let allergens: [String]
    let items: [String]
}

struct Reminder: Identifiable, Codable {
    var id = UUID().uuidString
    var title: String
    var detail: String
    var on: Bool
    var created = Date()
}

struct GroceryItem: Identifiable, Codable {
    var id = UUID().uuidString
    var name: String
    var done = false
    var created = Date()
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

/// All app state for one signed-in user, kept in sync with Firestore.
///
/// Layout (rules in /firestore.rules only let the owner read or write):
///   users/{uid}                 Profile
///   users/{uid}/logs/{yyyy-MM-dd} DayLog
///   users/{uid}/reminders/{id}  Reminder
///   users/{uid}/grocery/{id}    GroceryItem
///
/// Writes go straight to Firestore; the snapshot listeners update the arrays below
/// (immediately for local writes, and offline thanks to Firestore's cache).
@MainActor @Observable
final class CycleStore {
    var tab: Tab = .today
    var showLog = false
    var toast: String?

    let uid: String
    let today: Date

    /// Nil until onboarding is done. `loaded` flips once the first profile snapshot arrives.
    private(set) var profile: Profile?
    private(set) var loaded = false
    private(set) var logs: [DayLog] = []
    private(set) var reminders: [Reminder] = []
    private(set) var grocery: [GroceryItem] = []
    var messages: [ChatMessage] = []

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private let db = Firestore.firestore()
    private var userRef: DocumentReference { db.collection("users").document(uid) }

    var name: String { profile?.name ?? "" }
    var periodLength: Int { profile?.periodLength ?? 5 }
    var diets: Set<String> { Set(profile?.diets ?? []) }
    var avoid: Set<String> { Set(profile?.avoid ?? []) }

    static let demoLengths = [28, 31, 27, 29, 30] // most recent completed cycle first
    nonisolated static let cal = Calendar.current
    nonisolated static func add(_ date: Date, _ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: date)! }
    nonisolated static func days(_ a: Date, from b: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: b), to: cal.startOfDay(for: a)).day ?? 0
    }
    nonisolated static func key(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static let symptomOptions = ["Cramps", "Headache", "Bloating", "Tender breasts", "Back pain", "Acne", "Fatigue", "Cravings", "Trouble sleeping"]
    static let moodOptions = ["Calm", "Happy", "Confident", "Tired", "Anxious", "Irritable", "Low", "Sensitive"]
    static let dietOptions = ["vegetarian", "vegan", "gluten-free", "dairy-free"]
    static let allergenOptions = ["nuts", "dairy", "gluten", "soy", "eggs", "fish", "sesame"]
    static let nhsPeriodPain = URL(string: "https://www.nhs.uk/conditions/period-pain/")!
    static let nhsHeavyPeriods = URL(string: "https://www.nhs.uk/conditions/heavy-periods/")!

    init(uid: String) {
        self.uid = uid
        today = Self.cal.startOfDay(for: .now)
        listen()
    }

    // MARK: Sync

    private func listen() {
        listeners = [
            userRef.addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error { print("Profile listener:", error) }
                    self.profile = try? snap?.data(as: Profile.self)
                    self.loaded = true
                    if self.profile != nil, self.messages.isEmpty { self.greet() }
                }
            },
            userRef.collection("logs").addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    if let error { print("Logs listener:", error) }
                    self?.logs = snap?.documents.compactMap { try? $0.data(as: DayLog.self) } ?? []
                }
            },
            userRef.collection("reminders").order(by: "created", descending: true).addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    if let error { print("Reminders listener:", error) }
                    self?.reminders = snap?.documents.compactMap { try? $0.data(as: Reminder.self) } ?? []
                }
            },
            userRef.collection("grocery").order(by: "created").addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    if let error { print("Grocery listener:", error) }
                    self?.grocery = snap?.documents.compactMap { try? $0.data(as: GroceryItem.self) } ?? []
                }
            },
        ]
    }

    /// Detach listeners; call when the user signs out.
    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    private func greet() {
        messages = [ChatMessage(
            fromUser: false,
            text: "Hi \(name). You're on day \(cycleDay), in your \(currentPhase.name.lowercased()) phase. Your next period will probably start between \(fmt(windowStart)) and \(fmt(windowEnd)).",
            note: "I'm a wellness companion, not a doctor. I won't diagnose anything.")]
    }

    func updateProfile(name: String, lastPeriodStart: Date, cycleLength: Int, periodLength: Int) {
        userRef.updateData([
            "name": name,
            "lastPeriodStart": Timestamp(date: Self.cal.startOfDay(for: lastPeriodStart)),
            "cycleLength": cycleLength,
            "periodLength": periodLength,
        ]) { error in if let error { print("Profile update failed:", error) } }
        showToast("Settings saved")
    }

    /// Writes the profile plus a few default reminders the first time someone signs in.
    func completeOnboarding(name: String, lastPeriodStart: Date, cycleLength: Int, periodLength: Int) {
        let profile = Profile(name: name, lastPeriodStart: Self.cal.startOfDay(for: lastPeriodStart),
                              cycleLength: cycleLength, periodLength: periodLength)
        let batch = db.batch()
        try? batch.setData(from: profile, forDocument: userRef)
        let next = Self.add(profile.lastPeriodStart, cycleLength)
        let defaults = [
            Reminder(title: "Pack your period kit", detail: "\(fmt(Self.add(next, -3))) · before your likely window", on: true),
            Reminder(title: "Evening check-in", detail: "Every day · 8:30 pm", on: true),
            Reminder(title: "Restock pads & tampons", detail: "\(fmt(Self.add(next, -6))) · once", on: false),
        ]
        for (i, var r) in defaults.enumerated() {
            r.created = Date().addingTimeInterval(-Double(i)) // keep this order under created-desc sorting
            try? batch.setData(from: r, forDocument: userRef.collection("reminders").document(r.id))
        }
        batch.commit { error in if let error { print("Onboarding write failed:", error) } }
    }

    // MARK: Cycle maths

    /// Period start dates, most recent first: any logged flow that follows two flow-free days,
    /// plus the onboarding answer. Starts less than 10 days apart count as one period.
    var starts: [Date] {
        let flowDays = Set(logs.filter { $0.flow != "None" }.map { Self.cal.startOfDay(for: $0.date) })
        var candidates = flowDays.filter { !flowDays.contains(Self.add($0, -1)) && !flowDays.contains(Self.add($0, -2)) }
        if let seed = profile?.lastPeriodStart { candidates.insert(Self.cal.startOfDay(for: seed)) }
        var result: [Date] = []
        for d in candidates.sorted() where result.last.map({ Self.days(d, from: $0) >= 10 }) ?? true {
            result.append(d)
        }
        return result.isEmpty ? [today] : result.reversed()
    }

    /// Finished cycles, most recent first. Gaps outside 18–45 days are treated as missed logging.
    var completedCycles: [(start: Date, length: Int)] {
        let s = starts
        return zip(s.dropFirst(), s)
            .map { (start: $0, length: Self.days($1, from: $0)) }
            .filter { (18...45).contains($0.length) }
            .prefix(6)
            .map { $0 }
    }

    /// Never empty: falls back to the cycle length given during onboarding.
    var pastLengths: [Int] {
        let lengths = completedCycles.map(\.length)
        return lengths.isEmpty ? [profile?.cycleLength ?? 28] : lengths
    }

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
        date <= today && (logs.contains { $0.flow != "None" && Self.cal.isDate($0.date, inSameDayAs: date) }
            || starts.contains { let x = Self.days(date, from: $0); return x >= 0 && x < periodLength })
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

    var todayLog: DayLog? { logs.first { Self.cal.isDate($0.date, inSameDayAs: today) } }

    func save(_ log: DayLog) {
        try? userRef.collection("logs").document(log.id).setData(from: log)
        showLog = false
        let tags = log.moods.count + log.symptoms.count
        showToast("Saved · \(tags == 0 ? "no" : "\(tags)") tags logged")
    }

    func setReminder(_ reminder: Reminder, on: Bool) {
        userRef.collection("reminders").document(reminder.id).updateData(["on": on])
    }

    func toggleDiet(_ diet: String) { toggle("diets", diet, diets.contains(diet)) }
    func toggleAvoid(_ allergen: String) { toggle("avoid", allergen, avoid.contains(allergen)) }

    private func toggle(_ field: String, _ value: String, _ present: Bool) {
        userRef.updateData([field: present ? FieldValue.arrayRemove([value]) : FieldValue.arrayUnion([value])])
    }

    func toggleGrocery(_ item: GroceryItem) {
        userRef.collection("grocery").document(item.id).updateData(["done": !item.done])
    }

    /// Deletes every document this user owns. The profile goes too, so they land back on onboarding.
    func deleteAllData() {
        let refs = logs.map { userRef.collection("logs").document($0.id) }
            + reminders.map { userRef.collection("reminders").document($0.id) }
            + grocery.map { userRef.collection("grocery").document($0.id) }
            + [userRef]
        // Firestore batches are capped at 500 writes.
        for chunk in stride(from: 0, to: refs.count, by: 450).map({ refs[$0..<min($0 + 450, refs.count)] }) {
            let batch = db.batch()
            chunk.forEach { batch.deleteDocument($0) }
            batch.commit { error in if let error { print("Delete failed:", error) } }
        }
        messages = []
        tab = .today
        showToast("Your data was deleted")
    }

    #if DEBUG
    /// Writes five past cycles of made-up logs so the charts have something to show in a demo.
    func addSampleHistory() {
        var s = [lastStart]
        for length in Self.demoLengths { s.append(Self.add(s.last!, -length)) }
        let batch = db.batch()
        let write = { (log: DayLog) in try? batch.setData(from: log, forDocument: self.userRef.collection("logs").document(log.id)) }
        for start in s.dropFirst() {
            write(DayLog(date: start, flow: "Heavy", symptoms: ["Cramps", "Fatigue"]))
            write(DayLog(date: Self.add(start, 1), flow: "Medium", symptoms: ["Cramps", "Back pain"]))
            write(DayLog(date: Self.add(start, 2), flow: "Light", symptoms: ["Fatigue"]))
            write(DayLog(date: Self.add(start, -2), symptoms: ["Bloating", "Cravings"]))
            write(DayLog(date: Self.add(start, -4), symptoms: ["Tender breasts", "Trouble sleeping"]))
        }
        batch.commit { error in if let error { print("Sample history failed:", error) } }
        showToast("Added sample history")
    }
    #endif

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
        let batch = db.batch()
        if isOnList(meal) {
            for item in grocery where meal.items.contains(item.name) {
                batch.deleteDocument(userRef.collection("grocery").document(item.id))
            }
            showToast("Removed from grocery list")
        } else {
            for name in meal.items where !grocery.contains(where: { $0.name == name }) {
                let item = GroceryItem(name: name)
                try? batch.setData(from: item, forDocument: userRef.collection("grocery").document(item.id))
            }
            showToast("Added \(meal.items.count) items to your list")
        }
        batch.commit()
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
            let reminder = Reminder(title: title, detail: "\(fmt(Self.add(windowStart, -2))) · once", on: true)
            try? userRef.collection("reminders").document(reminder.id).setData(from: reminder)
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
