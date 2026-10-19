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
    /// The user's own tags, shown next to the built-in ones. Optional so older profiles still decode.
    var customMoods: [String]? = nil
    var customSymptoms: [String]? = nil
    /// Answers from "Edit cycle details". Optional so older profiles still decode.
    var baseline: CycleBaseline? = nil
}

/// One suggestion on Today's "Your plan for today" card.
struct PlanItem: Codable, Hashable {
    let icon: String
    let title: String
    let detail: String
}

struct Meal: Identifiable, Codable {
    var id = UUID()
    let name: String
    let why: String
    let diets: [String]
    let allergens: [String]
    /// Plain item names for the grocery list.
    let items: [String]
    // Recipe details; only AI-generated meals have them.
    var minutes: Int? = nil
    var servings: Int? = nil
    var ingredients: [String] = []
    var steps: [String] = []
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
///   users/{uid}/periods/{id}    PeriodRecord
///
/// Writes go straight to Firestore; the snapshot listeners update the arrays below
/// (immediately for local writes, and offline thanks to Firestore's cache).
@MainActor @Observable
final class CycleStore {
    private(set) var periodHistory = PeriodHistory()
    var periodStorageError: String?
    private var periodsRef: CollectionReference { userRef.collection("periods") }

    /// Validates against the loaded history, then writes the one changed record to Firestore.
    func savePeriod(id: UUID? = nil, start: Date, end: Date?) throws {
        var next = periodHistory
        try next.save(id: id, start: start, end: end)
        guard let saved = next.records.first(where: { !periodHistory.records.contains($0) }) else { return }
        try periodsRef.document(saved.id.uuidString).setData(from: saved) { error in
            if let error { self.showToast("Couldn't save period: \(error.localizedDescription)") }
        }
        periodHistory = next
    }

    func removePeriod(id: UUID) throws {
        periodsRef.document(id.uuidString).delete { error in
            if let error { self.showToast("Couldn't delete period: \(error.localizedDescription)") }
        }
        periodHistory.remove(id: id)
    }

    var baseline: CycleBaseline? { profile?.baseline }
    var showCycleSetup = false
    /// Recorded on the calendar or logged with flow. Never inferred from predictions.
    func hasPeriod(on date: Date) -> Bool {
        periodHistory.contains(date) || log(for: date).map { $0.flow != "None" } == true
    }
    private var backfillKey: String { "petal.flowBackfill.v2.\(uid)" }

    /// Flow logged before period records existed only showed as a tint. Turn it into records one time,
    /// reading from the server so a stale cache can't cause duplicates, and so deleting a record later sticks.
    private func backfillFlowPeriods() async {
        guard !UserDefaults.standard.bool(forKey: backfillKey) else { return }
        do {
            let logDocs = try await userRef.collection("logs").getDocuments(source: .server).documents
            let periodDocs = try await periodsRef.getDocuments(source: .server).documents
            periodHistory = PeriodHistory(records: periodDocs.compactMap { try? $0.data(as: PeriodRecord.self) })
            let flowDays = logDocs.compactMap { try? $0.data(as: DayLog.self) }.filter { $0.flow != "None" }.map(\.date).sorted()
            flowDays.forEach(recordFlow)
            UserDefaults.standard.set(true, forKey: backfillKey)
        } catch {
            print("Period backfill failed, will retry next launch:", error)
        }
    }

    /// Logging flow on a day no period covers starts one (or extends one that ended within two days),
    /// so the calendar controls and period history see it.
    private func recordFlow(on date: Date) {
        let day = Self.cal.startOfDay(for: date)
        if periodHistory.contains(day) || ongoingPeriod.map({ $0.start <= day }) == true { return }
        if let previous = periodHistory.records.first(where: { record in
            record.end.map { $0 < day && Self.days(day, from: $0) <= 2 } ?? false
        }) {
            try? savePeriod(id: previous.id, start: previous.start, end: day)
        } else {
            // Recent flow is probably still going; older flow is a one-day record the user can extend.
            let ongoing = ongoingPeriod == nil && Self.days(today, from: day) < periodLength
            try? savePeriod(start: day, end: ongoing ? nil : day)
        }
    }

    /// Start of the period `date` probably falls in: an ongoing record runs its usual length,
    /// stretched to today if longer; a start from logged flow runs its usual length.
    /// Display only; nothing is saved until the user records an end date.
    func expectedPeriodStart(for date: Date) -> Date? {
        let start: Date, end: Date
        if let active = ongoingPeriod {
            start = Self.cal.startOfDay(for: active.start)
            end = max(today, Self.add(start, periodLength - 1))
        } else if !periodHistory.contains(lastStart) {
            start = lastStart
            end = Self.add(start, periodLength - 1)
        } else { return nil }
        let day = Self.cal.startOfDay(for: date)
        return day >= start && day <= end ? start : nil
    }
    /// The recorded period `date` falls in. One with no end yet covers its usual length,
    /// or up to today if it has run longer.
    func period(on date: Date) -> PeriodRecord? {
        let day = Self.cal.startOfDay(for: date)
        return periodHistory.records.first { record in
            let start = Self.cal.startOfDay(for: record.start)
            let end = record.end.map { Self.cal.startOfDay(for: $0) } ?? max(today, Self.add(start, periodLength - 1))
            return start <= day && day <= end
        }
    }
    var ongoingPeriod: PeriodRecord? { periodHistory.records.first { $0.end == nil } }
    /// Also updates the profile fields every estimate reads, so Settings and the Today card agree.
    func saveBaseline(_ value: CycleBaseline, ongoing: Bool) throws {
        if ongoing, let start = value.lastStart, ongoingPeriod == nil {
            try savePeriod(start: start, end: nil)
        }
        var fields: [String: Any] = ["baseline": try Firestore.Encoder().encode(value), "periodLength": value.periodDays]
        if let start = value.lastStart { fields["lastPeriodStart"] = Timestamp(date: Self.cal.startOfDay(for: start)) }
        if let days = value.cycleDays { fields["cycleLength"] = days }
        userRef.updateData(fields) { error in if let error { print("Baseline update failed:", error) } }
        showCycleSetup = false
    }

    var tab: Tab = .today
    var showLog = false
    /// Day to open in LogSheet when editing a past entry; nil means today.
    var selectedLogDate: Date?
    var selectedCalendarDate: Date?
    var toast: String?

    let uid: String
    var today: Date

    /// Nil until onboarding is done. `loaded` flips once the first profile snapshot arrives.
    private(set) var profile: Profile?
    private(set) var loaded = false
    private(set) var logs: [DayLog] = []
    private(set) var logsLoaded = false
    private(set) var logsError: String?
    private(set) var logWritePending = false
    private(set) var logWriteError: String?
    private(set) var reminders: [Reminder] = []
    private(set) var grocery: [GroceryItem] = []
    var messages: [ChatMessage] = []
    /// True while the companion is waiting on the model.
    private(set) var thinking = false

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private let db = Firestore.firestore()
    /// Created on first message so the prompt sees the loaded profile. Reset when data is deleted.
    @ObservationIgnored private var assistant: Assistant?
    /// Cycle facts baked into the assistant's prompt; when they change, a fresh assistant is created.
    @ObservationIgnored private var assistantFacts = ""
    private var historyRevision = 0
    private func invalidateComparisonConversation() { historyRevision += 1 }
    private var userRef: DocumentReference { db.collection("users").document(uid) }

    var name: String { profile?.name ?? "" }
    var periodLength: Int { profile?.periodLength ?? 5 }
    var diets: Set<String> { Set(profile?.diets ?? []) }
    var avoid: Set<String> { Set(profile?.avoid ?? []) }

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
        Task { await backfillFlowPeriods() }
    }

    // MARK: Sync

    private func listen() {
        listeners = [
            userRef.addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error { print("Profile listener:", error) }
                    self.profile = try? snap?.data(as: Profile.self)
                    self.invalidateComparisonConversation()
                    self.loaded = true
                    self.syncNotifications()
                    self.prefetchAI()
                }
            },
            userRef.collection("logs").addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.logsLoaded = true
                    if let error {
                        self.logsError = "Could not load symptom history: \(error.localizedDescription)"
                        return
                    }
                    do {
                        self.logs = try (snap?.documents ?? []).map { try $0.data(as: DayLog.self) }
                        self.logsError = nil
                    } catch {
                        self.logsError = "Some saved entries could not be read. Comparison is unavailable until history can be loaded."
                        return
                    }
                    self.invalidateComparisonConversation()
                    self.syncNotifications() // predictions may have moved
                    self.prefetchAI()
                }
            },
            periodsRef.addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    if let error { print("Periods listener:", error) }
                    self?.periodHistory = PeriodHistory(records: snap?.documents.compactMap { try? $0.data(as: PeriodRecord.self) } ?? [])
                    self?.invalidateComparisonConversation()
                    self?.syncNotifications() // predictions may have moved
                    self?.prefetchAI()
                }
            },
            userRef.collection("reminders").order(by: "created", descending: true).addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error { print("Reminders listener:", error) }
                    let docs = snap?.documents ?? []
                    self.reminders = docs.compactMap { try? $0.data(as: Reminder.self) }
                    // Reminders from before schedules existed have no "kind"; swap them for the new defaults.
                    let legacy = docs.filter { $0.data()["kind"] == nil }.map(\.reference)
                    if !legacy.isEmpty { self.replaceLegacyReminders(legacy, seedDefaults: legacy.count == docs.count) }
                    self.syncNotifications()
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

    /// The Companion's opening message. Computed, not stored, so it updates as soon as a log changes the prediction.
    var greeting: ChatMessage {
        ChatMessage(
            fromUser: false,
            text: "Hi \(name). You're on day \(cycleDay), in your \(currentPhase.name.lowercased()) phase. Your next period will probably start between \(fmt(windowStart)) and \(fmt(windowEnd)).",
            note: "I'm a wellness companion, not a doctor. I won't diagnose anything.")
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
        addDefaultReminders(to: batch)
        batch.commit { error in if let error { print("Onboarding write failed:", error) } }
        ReminderNotifications.requestPermission()
    }

    private func addDefaultReminders(to batch: WriteBatch) {
        for (i, var r) in Reminder.defaults.enumerated() {
            r.created = Date().addingTimeInterval(-Double(i)) // keep this order under created-desc sorting
            try? batch.setData(from: r, forDocument: userRef.collection("reminders").document(r.id))
        }
    }

    private func replaceLegacyReminders(_ refs: [DocumentReference], seedDefaults: Bool) {
        let batch = db.batch()
        refs.forEach { batch.deleteDocument($0) }
        if seedDefaults { addDefaultReminders(to: batch) }
        batch.commit { error in if let error { print("Reminder migration failed:", error) } }
    }

    private func syncNotifications() {
        guard profile != nil else { return }
        ReminderNotifications.sync(reminders, windowStart: windowStart)
    }

    // MARK: Cycle maths

    /// Period start dates, most recent first: any logged flow that follows two flow-free days,
    /// periods recorded on the calendar, plus the onboarding answer. Starts less than 10 days apart count as one period.
    var starts: [Date] {
        let flowDays = Set(logs.filter { $0.flow != "None" }.map { Self.cal.startOfDay(for: $0.date) })
        var candidates = flowDays.filter { !flowDays.contains(Self.add($0, -1)) && !flowDays.contains(Self.add($0, -2)) }
        candidates.formUnion(periodHistory.records.map { Self.cal.startOfDay(for: $0.start) })
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

    /// A phase can be absent when the cycle is too short for the usual offsets.
    /// Clamp derived boundaries only; never rewrite the user's saved lengths.
    nonisolated static func phaseRange(of phase: Phase, cycleLength: Int, periodLength: Int) -> ClosedRange<Int>? {
        let length = max(1, cycleLength)
        let bleedingEnd = min(length, max(1, periodLength))
        let follicularEnd = max(bleedingEnd, length - min(length, 16))
        let midEnd = max(follicularEnd, length - min(length, 12))

        switch phase {
        case .menstrual:
            return 1...bleedingEnd
        case .follicular:
            guard follicularEnd > bleedingEnd else { return nil }
            return (bleedingEnd + 1)...follicularEnd
        case .mid:
            guard midEnd > follicularEnd else { return nil }
            return (follicularEnd + 1)...midEnd
        case .luteal:
            guard length > midEnd else { return nil }
            return (midEnd + 1)...length
        }
    }

    func range(of phase: Phase) -> ClosedRange<Int>? {
        Self.phaseRange(of: phase, cycleLength: average, periodLength: periodLength)
    }

    func phase(forDay day: Int) -> Phase {
        Phase.allCases.first { range(of: $0)?.contains(day) == true } ?? .luteal
    }
    var currentPhase: Phase { phase(forDay: cycleDay) }

    func isPeriod(_ date: Date) -> Bool {
        date <= today && (periodHistory.contains(date) || logs.contains { $0.flow != "None" && Self.cal.isDate($0.date, inSameDayAs: date) }
            || starts.contains { let x = Self.days(date, from: $0); return x >= 0 && x < periodLength })
    }
    func isPredicted(_ date: Date) -> Bool {
        let x = Self.days(date, from: nextStart); return x >= 0 && x < periodLength
    }
    func isMaybe(_ date: Date) -> Bool {
        !isPredicted(date) && date >= windowStart && date <= Self.add(windowEnd, periodLength - 1)
    }

    var comparisonCycles: [ComparedCycle] {
        let confirmed = periodHistory.records.map(\.start)
        let entries = logs.map {
            ComparisonEntry.databaseEntry(id: $0.id, date: $0.date, symptoms: $0.symptoms,
                pain: $0.pain, note: $0.note)
        }
        return SymptomComparisonEngine.cycles(starts: confirmed, logs: entries, asOf: today)
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

    func log(for date: Date) -> DayLog? {
        logs.first { Self.cal.isDate($0.date, inSameDayAs: date) }
    }

    /// Logs are keyed by day, so saving replaces that day's entry (not necessarily today's).
    func save(_ log: DayLog) {
        guard !logWritePending else { return }
        logWritePending = true
        logWriteError = nil
        Task {
            defer { logWritePending = false }
            do {
                try await write(log)
                showLog = false
                selectedLogDate = nil
                showToast("Entry saved")
            } catch {
                logWriteError = "Entry was not saved: \(error.localizedDescription)"
            }
        }
    }

    /// Saves a log and waits for Firestore to accept it, so the assistant only confirms real saves.
    func write(_ log: DayLog) async throws {
        guard Self.cal.startOfDay(for: log.date) <= today, (0...10).contains(log.pain), (1...5).contains(log.energy),
              log.symptoms.count <= 20, log.moods.count <= 20, log.note.count <= 2000 else {
            throw NSError(domain: "PetalLog", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Check date, ratings, at most 20 tags per category, and note length (2000 characters)."])
        }
        try await set(log, at: userRef.collection("logs").document(log.id))
        if log.flow != "None" { recordFlow(on: log.date) }
    }

    /// Saves a reminder and waits for Firestore, so the assistant only confirms real saves.
    func addReminder(_ reminder: Reminder) async throws {
        try await set(reminder, at: userRef.collection("reminders").document(reminder.id))
        ReminderNotifications.requestPermission()
    }

    private func set<T: Encodable>(_ value: T, at ref: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            do {
                try ref.setData(from: value) { error in
                    if let error { done.resume(throwing: error) } else { done.resume() }
                }
            } catch {
                done.resume(throwing: error)
            }
        }
    }

    func deleteLog(_ log: DayLog) {
        logWriteError = nil
        userRef.collection("logs").document(log.id).delete { [weak self] error in
            Task { @MainActor in
                if let error { self?.logWriteError = "Entry was not deleted: \(error.localizedDescription)" }
                else { self?.showToast("Entry deleted") }
            }
        }
    }

    func setReminder(_ reminder: Reminder, on: Bool) {
        userRef.collection("reminders").document(reminder.id).updateData(["on": on])
        if on { ReminderNotifications.requestPermission() }
    }

    func saveReminder(_ reminder: Reminder) {
        try? userRef.collection("reminders").document(reminder.id).setData(from: reminder)
        ReminderNotifications.requestPermission()
        showToast("Reminder saved")
    }

    func deleteReminder(_ reminder: Reminder) {
        userRef.collection("reminders").document(reminder.id).delete()
        showToast("Reminder deleted")
    }

    var allMoods: [String] { Self.moodOptions + (profile?.customMoods ?? []) }
    var allSymptoms: [String] { Self.symptomOptions + (profile?.customSymptoms ?? []) }

    /// Adds a custom mood or symptom to the user's list. Returns the cleaned-up name, or nil if it's empty/too long.
    @discardableResult
    func addCustom(symptom: Bool, _ name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 30 else { return nil }
        let tag = clean.prefix(1).uppercased() + clean.dropFirst()
        let existing = symptom ? allSymptoms : allMoods
        if let match = existing.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return match }
        userRef.updateData([symptom ? "customSymptoms" : "customMoods": FieldValue.arrayUnion([tag])])
        return tag
    }

    func removeCustom(symptom: Bool, _ name: String) {
        userRef.updateData([symptom ? "customSymptoms" : "customMoods": FieldValue.arrayRemove([name])])
    }

    func toggleDiet(_ diet: String) { toggle("diets", diet, diets.contains(diet)) }
    func toggleAvoid(_ allergen: String) { toggle("avoid", allergen, avoid.contains(allergen)) }

    private func toggle(_ field: String, _ value: String, _ present: Bool) {
        userRef.updateData([field: present ? FieldValue.arrayRemove([value]) : FieldValue.arrayUnion([value])])
    }

    func toggleGrocery(_ item: GroceryItem) {
        userRef.collection("grocery").document(item.id).updateData(["done": !item.done])
    }

    /// Clears only the grocery items currently shown, including checked items.
    /// Snapshot listeners update the list and each meal's Added state.
    func clearGroceryList() async throws {
        let refs = grocery.map { userRef.collection("grocery").document($0.id) }
        for offset in stride(from: 0, to: refs.count, by: 450) {
            let batch = db.batch()
            refs[offset..<min(offset + 450, refs.count)].forEach { batch.deleteDocument($0) }
            try await batch.commit()
        }
        showToast("Grocery list cleared")
    }

    /// Deletes every document this user owns and waits for Firestore to confirm.
    /// The profile goes too, so they land back on onboarding.
    func deleteAllData() async throws {
        let cached = try await cacheRef.getDocuments().documents.map(\.reference)
        let refs = logs.map { userRef.collection("logs").document($0.id) }
            + reminders.map { userRef.collection("reminders").document($0.id) }
            + grocery.map { userRef.collection("grocery").document($0.id) }
            + periodHistory.records.map { periodsRef.document($0.id.uuidString) }
            + cached
            + [userRef]
        // Firestore batches are capped at 500 writes.
        for chunk in stride(from: 0, to: refs.count, by: 450).map({ refs[$0..<min($0 + 450, refs.count)] }) {
            let batch = db.batch()
            chunk.forEach { batch.deleteDocument($0) }
            try await batch.commit()
        }
        aiMeals = [:]
        plan = nil
        messages = []
        assistant = nil
        ReminderNotifications.sync([], windowStart: windowStart)
        tab = .today
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

    // MARK: AI meal ideas

    /// Generated recipes for this session, keyed by phase + preferences (see mealKey).
    private(set) var aiMeals: [String: [Meal]] = [:]
    private(set) var mealsLoading: Set<String> = []
    private(set) var mealsFailed: Set<String> = []

    // AI results are cached in users/{uid}/cache so they show instantly next time and are only
    // regenerated when their inputs change.
    private var cacheRef: CollectionReference { userRef.collection("cache") }
    private static let mealCacheDays = 7

    func mealKey(_ phase: Phase) -> String {
        "\(phase.rawValue)|\(diets.sorted().joined(separator: ","))|\(avoid.sorted().joined(separator: ","))"
    }

    /// What Nourish shows: AI recipes once loaded, otherwise the built-in ideas.
    func shownMeals(for phase: Phase) -> [Meal] { aiMeals[mealKey(phase)] ?? meals(for: phase) }

    func loadMeals(for phase: Phase, refresh: Bool = false) async {
        let key = mealKey(phase)
        guard refresh || aiMeals[key] == nil, !mealsLoading.contains(key) else { return }
        mealsLoading.insert(key)
        mealsFailed.remove(key)
        defer { mealsLoading.remove(key) }
        let doc = cacheRef.document("meals-" + key)
        if !refresh, let cached = try? await doc.getDocument(as: CachedMeals.self),
           cached.created > Self.add(.now, -Self.mealCacheDays) {
            aiMeals[key] = cached.meals.filter(fitsPreferences)
            return
        }
        do {
            let ideas = try await Assistant.mealIdeas(for: phase, diets: diets, avoid: avoid, recentSymptoms: recentSymptoms,
                                                      notLike: aiMeals[key]?.map(\.name) ?? [])
            let safe = ideas.filter(fitsPreferences)
            if safe.isEmpty { throw CancellationError() }
            aiMeals[key] = safe
            try? doc.setData(from: CachedMeals(meals: safe, created: .now))
        } catch {
            print("Meal ideas failed:", error)
            mealsFailed.insert(key)
        }
    }

    private struct CachedMeals: Codable {
        let meals: [Meal]
        let created: Date
    }

    /// Symptoms logged in the last 3 days, most frequent first.
    var recentSymptoms: [String] {
        let since = Self.add(today, -3)
        var counts: [String: Int] = [:]
        for log in logs where log.date >= since { for s in log.symptoms { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: AI plan for today

    /// nil until loaded; Today shows the built-in suggestions meanwhile.
    private(set) var plan: [PlanItem]?
    private(set) var planLoading = false

    /// Everything the plan depends on. When this text changes, the plan is regenerated.
    var planContext: String {
        let todayEntry = log(for: today)
        let yesterday = log(for: Self.add(today, -1))
        var lines = [
            "Date: \(today.formatted(.dateTime.weekday(.wide).month(.wide).day())). Cycle day \(cycleDay), \(currentPhase.name.lowercased()) phase. \(currentPhase.blurb)",
            "Diet: \(diets.isEmpty ? "no restrictions" : diets.sorted().joined(separator: ", ")). Avoid: \(avoid.isEmpty ? "nothing" : avoid.sorted().joined(separator: ", ")).",
        ]
        if let e = todayEntry {
            lines.append("Logged today: flow \(e.flow); moods \(e.moods.isEmpty ? "none" : e.moods.joined(separator: ", ")); symptoms \(e.symptoms.isEmpty ? "none" : e.symptoms.joined(separator: ", ")); pain \(e.pain)/10; energy \(e.energy)/5.")
        } else {
            lines.append("Nothing logged yet today.")
        }
        if let yesterday, !yesterday.symptoms.isEmpty {
            lines.append("Yesterday's symptoms: \(yesterday.symptoms.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    func loadPlan() async {
        let context = planContext
        guard !planLoading else { return }
        planLoading = true
        defer { planLoading = false }
        let doc = cacheRef.document("plan")
        if let cached = try? await doc.getDocument(as: CachedPlan.self), cached.context == context {
            plan = cached.items
            return
        }
        do {
            let items = try await Assistant.dailyPlan(context: context)
                .filter { Assistant.planIcons.contains($0.icon) && !$0.title.isEmpty }
            guard !items.isEmpty, context == planContext else { return } // inputs changed mid-flight; the next call handles it
            plan = Array(items.prefix(3))
            try? doc.setData(from: CachedPlan(items: Array(items.prefix(3)), context: context))
        } catch {
            print("Daily plan failed:", error)
        }
    }

    private struct CachedPlan: Codable {
        let items: [PlanItem]
        let context: String
    }

    /// Start AI work early so Today and Nourish are ready by the time the user looks.
    private func prefetchAI() {
        guard profile != nil else { return }
        Task {
            await loadPlan()
            await loadMeals(for: currentPhase)
        }
    }

    /// Second check on AI recipes: the model's own labels, then a keyword scan of the ingredients.
    private func fitsPreferences(_ meal: Meal) -> Bool {
        guard diets.allSatisfy(meal.diets.contains), !meal.allergens.contains(where: avoid.contains) else { return false }
        let text = ([meal.name] + meal.ingredients + meal.items).joined(separator: " ").lowercased()
        return !avoid.contains { allergen in
            var scanned = text
            for phrase in Self.allergenLookalikes[allergen] ?? [] { scanned = scanned.replacingOccurrences(of: phrase, with: " ") }
            return (Self.allergenWords[allergen] ?? [allergen]).contains {
                scanned.range(of: "\\b\($0)", options: .regularExpression) != nil
            }
        }
    }

    private static let allergenWords: [String: [String]] = [
        "nuts": ["nut", "almond", "cashew", "walnut", "pecan", "hazelnut", "pistachio", "macadamia", "pesto", "praline", "marzipan"],
        "dairy": ["milk", "cheese", "yogurt", "yoghurt", "butter", "cream", "parmesan", "feta", "mozzarella", "ghee", "whey", "paneer"],
        "gluten": ["wheat", "flour", "bread", "pasta", "couscous", "barley", "rye", "spelt", "sourdough", "noodle", "soy sauce", "seitan", "bulgur", "tortilla", "oats"],
        "soy": ["soy", "tofu", "tempeh", "edamame", "miso"],
        "eggs": ["egg"],
        "fish": ["fish", "salmon", "tuna", "cod", "anchov", "sardine", "mackerel", "trout", "haddock"],
        "sesame": ["sesame", "tahini"],
    ]

    /// Phrases that contain an allergen word but aren't that allergen; removed before scanning.
    private static let allergenLookalikes: [String: [String]] = [
        "nuts": ["coconut", "nutmeg", "butternut", "nutritional yeast", "nut-free"],
        "dairy": ["coconut milk", "oat milk", "almond milk", "soy milk", "rice milk", "plant milk", "plant-based milk",
                  "coconut yogurt", "coconut yoghurt", "soy yogurt", "dairy-free", "vegan cheese", "vegan butter",
                  "peanut butter", "almond butter", "nut butter", "cashew butter", "cocoa butter", "butternut", "coconut cream"],
        "gluten": ["gluten-free soy sauce", "gluten-free pasta", "gluten-free bread", "gluten-free flour", "gluten-free oats",
                   "gluten-free tortilla", "gluten-free", "buckwheat", "rice noodle", "rice flour", "corn tortilla", "almond flour", "coconut flour"],
        "soy": ["soy-free"],
        "eggs": ["eggplant", "egg-free"],
    ]

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
        // Urgent symptoms get the fixed safety reply without waiting on the model.
        if Self.needsCare(text) { return reply(to: text) }
        thinking = true
        Task {
            defer { thinking = false }
            do {
                let facts = "\(cycleDay)|\(windowStart)|\(windowEnd)|\(name)|\(historyRevision)"
                if assistant == nil || facts != assistantFacts {
                    assistant = Assistant(store: self)
                    assistantFacts = facts
                }
                let assistant = self.assistant!
                ai(try await assistant.reply(to: text), note: "AI-generated. Not medical advice.")
            } catch {
                // No connection, billing not set up, etc.: fall back to the built-in replies.
                print("Assistant failed:", error)
                reply(to: text)
            }
        }
    }

    private static func needsCare(_ text: String) -> Bool {
        let q = text.lowercased()
        return ["faint", "soak", "very heavy", "severe", "unbearable", "clot", "pass out"].contains { q.contains($0) }
    }

    func perform(_ action: ChatAction, from messageID: UUID) {
        if let i = messages.firstIndex(where: { $0.id == messageID }) { messages[i].actions = [] }
        switch action {
        case .setReminder(let title):
            saveReminder(Reminder(title: title, kind: .beforePeriod, hour: 9, minute: 0, daysBefore: 2))
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

        if Self.needsCare(question) {
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
