import SwiftUI
import Observation
import FirebaseFirestore

/// Exactly the deployed predictions/{cycleStart} schema; no encoded ID or accuracy fields.
struct AIForecast: Codable, Equatable {
    var cycleStart: String
    var baselineStart: String
    var baselineSpread: Int
    var shiftDays: Int
    var spreadDays: Int
    var predictedStart: String
    var reason: String
    /// Validated completed-cycle references supporting the forecast, if present.
    /// Optional so previously stored forecast documents continue to decode.
    var evidenceCycleStarts: [String]? = nil
    var model: String
    var inputsHash: String
    @ServerTimestamp var createdAt: Date?
}

struct ForecastMemory: Codable {
    var notes: [String]
    var basedOnCycles: Int
    @ServerTimestamp var updatedAt: Date?
}

enum Tab { case today, cycle, nourish, companion }

enum Phase: String, CaseIterable, Identifiable {
    case menstrual, follicular, ovulation, luteal
    var id: String { rawValue }

    var name: String {
        switch self {
        // "Period" stays for bleeding itself (logging, predictions); the phase is "Menstrual".
        case .menstrual: "Menstrual"
        case .follicular: "Follicular"
        case .ovulation: "Ovulation"
        case .luteal: "Luteal"
        }
    }

    var color: Color {
        switch self {
        case .menstrual: Palette.rose
        case .follicular: Palette.blush
        case .ovulation: Palette.pink
        case .luteal: Palette.berry
        }
    }

    var artColors: [Color] {
        switch self {
        case .menstrual: [Palette.rose, Palette.pink]
        case .follicular: [Palette.blush, Palette.mist]
        case .ovulation: [Palette.pink, Palette.blush]
        case .luteal: [Palette.berry, Palette.petal]
        }
    }

    var blurb: String {
        switch self {
        case .menstrual: "Iron-rich foods, warm meals and plenty of fluids are good general choices while you bleed. Rest counts too."
        case .follicular: "Many people feel lighter and more energetic now. Fresh, colourful meals with protein and fibre keep you going."
        case .ovulation: "A good time for whatever feels good: balanced plates, lots of veg, and staying hydrated if you're active."
        case .luteal: "Cravings and lower energy are common before a period. Regular meals with slow-release carbs can help you feel steadier."
        }
    }

    /// One-line version of `blurb` for the Nourish tip; the full text still goes to the AI prompts.
    var foodTip: String {
        switch self {
        case .menstrual: "Iron-rich, warm meals and plenty of fluids."
        case .follicular: "Fresh, colourful meals with protein and fibre."
        case .ovulation: "Balanced plates, lots of veg, and stay hydrated."
        case .luteal: "Slow-release carbs help with cravings and low energy."
        }
    }
}

/// users/{uid} — set during onboarding.
struct Profile: Codable {
    var name: String
    var lastPeriodStart: Date
    var cycleLength: Int
    var periodLength: Int
    var diets: [String] = []
    var avoid: [String] = []
    /// Foods to leave out of meal ideas. A soft preference, unlike `avoid`. Optional so older profiles still decode.
    var dislikes: [String]? = nil
    /// The user's own tags, shown next to the built-in ones. Optional so older profiles still decode.
    var customMoods: [String]? = nil
    var customSymptoms: [String]? = nil
    /// Personalization stays in the Firebase user profile; old profiles can omit these keys.
    var hiddenMoods: [String]? = nil
    var hiddenSymptoms: [String]? = nil
    var moodOrder: [String]? = nil
    var symptomOrder: [String]? = nil
    var moodEmojis: [String: String]? = nil
    var symptomEmojis: [String: String]? = nil
    /// Answers from "Edit cycle details". Optional so older profiles still decode.
    var baseline: CycleBaseline? = nil
    /// CoordinatedTheme raw value, so the palette follows the account across devices.
    var palette: String? = nil
    /// Optional for older profiles: enabled by default, but only with AI consent.
    var aiPredictions: Bool? = nil
    /// Whether the user agreed to send their data to Gemini. nil means never asked, which counts as no.
    var aiConsent: Bool? = nil
    /// nil means no birth control. Optional so older profiles still decode.
    var birthControl: BirthControl? = nil
}

/// How Sync reads the cycle: hormonal methods usually pause ovulation, so phases stop applying.
enum CycleMode {
    /// Four phases and period predictions.
    case natural
    /// Withdrawal bleeds predicted from the pack, patch or ring schedule. No phases.
    case pack
    /// No phases or predictions; bleeding can be irregular, so it's only logged.
    case steady
}

/// Stored on the profile as `birthControl`.
struct BirthControl: Codable, Equatable {
    enum Method: String, Codable, CaseIterable, Identifiable {
        case combinedPill, miniPill, patch, ring, shot, implant, hormonalIUD, copperIUD, other
        var id: String { rawValue }

        var name: String {
            switch self {
            case .combinedPill: "Combined pill"
            case .miniPill: "Mini-pill"
            case .patch: "Patch"
            case .ring: "Ring"
            case .shot: "Shot"
            case .implant: "Implant"
            case .hormonalIUD: "Hormonal IUD"
            case .copperIUD: "Copper IUD"
            case .other: "Other"
            }
        }

        /// Methods with a pack, patch or ring schedule that can include a planned break.
        var hasSchedule: Bool { [.combinedPill, .patch, .ring].contains(self) }
        var isPill: Bool { self == .combinedPill || self == .miniPill }
        /// What the schedule is called in "… started".
        var scheduleNoun: String {
            switch self {
            case .patch: "first patch"
            case .ring: "ring"
            default: "pack"
            }
        }
    }

    var method: Method
    /// First day of the current pack, patch or ring cycle. Later cycles repeat every 28 days from here.
    var packStart: Date? = nil
    /// Days before the break: 21 or 24. nil means no break, so no planned bleed.
    var activeDays: Int? = nil

    static let packLength = 28

    var mode: CycleMode {
        switch method {
        case .copperIUD, .other: .natural
        case .combinedPill, .patch, .ring: packStart != nil && activeDays != nil ? .pack : .steady
        case .miniPill, .shot, .implant, .hormonalIUD: .steady
        }
    }

    /// Break options shown for this method, as (active days, label).
    var regimens: [(days: Int?, label: String)] {
        method == .combinedPill
            ? [(21, "21 + 7 break"), (24, "24 + 4 break"), (nil, "No breaks")]
            : [(21, "3 weeks + 1 off"), (nil, "No breaks")]
    }
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
    var comparisons: [CycleComparison] = []
    var recordedCycles: [ComparedCycle] = []
    var savedLogs: [SavedLogResult] = []
    var educationCitations: [EducationCitation] = []
    var suggestedPrompts: [String] = []
}

struct SavedLogResult: Identifiable {
    let id = UUID()
    let from: Date
    let to: Date
    let logs: [DayLog]
}

struct AssistantReply {
    let text: String
    let comparisons: [CycleComparison]
    let recordedCycles: [ComparedCycle]
    let savedLogs: [SavedLogResult]
    let includesWellnessAdvice: Bool
    let educationCitations: [EducationCitation]
    var suggestedPrompts: [String] = []
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
            if let error { Task { @MainActor in self.showToast("Couldn't save period: \(error.localizedDescription)") } }
        }
        periodHistory = next
    }

    func removePeriod(id: UUID) throws {
        periodsRef.document(id.uuidString).delete { error in
            if let error { Task { @MainActor in self.showToast("Couldn't delete period: \(error.localizedDescription)") } }
        }
        periodHistory.remove(id: id)
    }

    var baseline: CycleBaseline? { profile?.baseline }
    var showCycleSetup = false
    /// Recorded on the calendar or logged with flow. Never inferred from predictions.
    func hasPeriod(on date: Date) -> Bool {
        periodHistory.contains(date)
    }
    private var backfillKey: String { "petal.flowBackfill.v2.\(uid)" }

    @ObservationIgnored private var backfillTask: Task<Void, Never>?
    private var deletingData = false

    /// Convert old flow logs once per account. Commit the records together before
    /// marking migration complete, so a rejected write is retried on next launch.
    private func backfillFlowPeriods() async {
        guard !UserDefaults.standard.bool(forKey: backfillKey) else { return }
        do {
            let logDocs = try await userRef.collection("logs").getDocuments(source: .server).documents
            let periodDocs = try await periodsRef.getDocuments(source: .server).documents
            try Task.checkCancellation()
            guard !deletingData else { return }
            let original = PeriodHistory(records: try periodDocs.map { try $0.data(as: PeriodRecord.self) })
            var next = original
            let entries = try logDocs.map { try $0.data(as: DayLog.self) }.sorted { $0.date < $1.date }
            var previousFlowDays: [Date] = []
            for entry in entries {
                try next.recordFlow(on: entry.date, flow: entry.flow, previousFlowDays: previousFlowDays,
                                    periodLength: periodLength, today: today)
                if entry.flow != "None" { previousFlowDays.append(entry.date) }
            }
            let changed = next.records.filter { !original.records.contains($0) }
            let removed = original.records.filter { record in !next.records.contains { $0.id == record.id } }
            // Stay below Firestore's 500-write limit for long histories.
            for offset in stride(from: 0, to: changed.count + removed.count, by: 450) {
                try Task.checkCancellation()
                guard !deletingData else { return }
                let batch = db.batch()
                for index in offset..<min(offset + 450, changed.count + removed.count) {
                    if index < changed.count {
                        let record = changed[index]
                        try batch.setData(from: record, forDocument: periodsRef.document(record.id.uuidString))
                    } else {
                        batch.deleteDocument(periodsRef.document(removed[index - changed.count].id.uuidString))
                    }
                }
                try await batch.commit()
            }
            try Task.checkCancellation()
            guard !deletingData else { return }
            periodHistory = next
            UserDefaults.standard.set(true, forKey: backfillKey)
        } catch is CancellationError {
            // Sign-out and data deletion cancel migration.
        } catch {
            print("Period backfill failed, will retry next launch:", error)
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
    var showingLogPreview = false
    var selectedCalendarDate: Date?
    var toast: String?

    let uid: String
    var today: Date

    /// Nil until onboarding is done. `loaded` flips once the first profile snapshot arrives.
    private(set) var profile: Profile?
    private(set) var loaded = false
    private(set) var profileError: String?
    private(set) var periodsLoaded = false
    private(set) var periodsError: String?
    private(set) var logs: [DayLog] = []
    private(set) var logsLoaded = false
    private(set) var logsError: String?
    private(set) var logWritePending = false
    private(set) var logWriteError: String?
    private(set) var reminders: [Reminder] = []
    private(set) var remindersLoaded = false
    private(set) var remindersError: String?
    private var reminderDeletion = ReminderDeletionConsent()
    private var reminderClarification = ReminderClarification()
    private(set) var grocery: [GroceryItem] = []
    var messages: [ChatMessage] = []
    private var loggingConversation = LoggingConversation()
    /// True while the companion is waiting on the model.
    private(set) var thinking = false
    private(set) var forecasts: [String: AIForecast] = [:]
    private(set) var forecastMemory: ForecastMemory?
    private(set) var forecastLoading = false
    private var forecastsAvailable = false
    private var forecastStopped = false
    private var forecastGeneration = 0
    private var forecastAttemptedHash: String?
    private var forecastFailureHash: String?
    private var forecastFailureCount = 0
    @ObservationIgnored private var forecastTask: Task<Void, Never>?
    @ObservationIgnored private var forecastTaskID: UUID?
    @ObservationIgnored private var forecastTaskHash: String?

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
    var dislikes: [String] { profile?.dislikes ?? [] }
    /// Chat, AI meal ideas and the AI daily plan only run with consent; everything else works without it.
    var aiEnabled: Bool { profile?.aiConsent == true }

    nonisolated static var cal: Calendar { LogDate.calendar }
    nonisolated static func add(_ date: Date, _ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: date)! }
    nonisolated static func days(_ a: Date, from b: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: b), to: cal.startOfDay(for: a)).day ?? 0
    }
    nonisolated static func key(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static let symptomOptions = ["Cramps", "Headache", "Bloating", "Tender breasts", "Back pain", "Acne", "Fatigue", "Cravings", "Trouble sleeping", "Low sex drive", "High sex drive"]
    static let moodOptions = ["Calm", "Happy", "Confident", "Tired", "Anxious", "Irritable", "Low", "Sensitive"]
    static let dietOptions = ["vegetarian", "vegan", "gluten-free", "dairy-free"]
    static let allergenOptions = ["nuts", "dairy", "gluten", "soy", "eggs", "fish", "sesame"]
    static let nhsPeriodPain = URL(string: "https://www.nhs.uk/conditions/period-pain/")!
    static let nhsHeavyPeriods = URL(string: "https://www.nhs.uk/conditions/heavy-periods/")!

    init(uid: String) {
        self.uid = uid
        today = Self.cal.startOfDay(for: .now)
        listen()
        backfillTask = Task { await backfillFlowPeriods() }
    }

    // MARK: Sync

    private func listen() {
        listeners = [
            userRef.addSnapshotListener { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.profileError = error.map { "Could not load profile: \($0.localizedDescription)" }
                    if error != nil { self.syncNotifications(); return }
                    // A brand-new account has no document yet: that's "needs onboarding", not an error.
                    if let snap, snap.exists {
                        do { self.profile = try snap.data(as: Profile.self) }
                        catch { self.profileError = "Could not read profile."; self.syncNotifications(); return }
                    } else {
                        self.profile = nil
                    }
                    self.applySavedPalette()
                    self.invalidateComparisonConversation()
                    self.loaded = true
                    self.syncNotifications()
                    self.prefetchAI()
                }
            },
            userRef.collection("logs").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.logsLoaded = true
                    if let error {
                        self.logsError = "Could not load symptom history: \(error.localizedDescription)"
                        self.syncNotifications()
                        return
                    }
                    guard snap?.metadata.hasPendingWrites != true else { return }
                    do {
                        self.logs = try (snap?.documents ?? []).map { try $0.data(as: DayLog.self) }
                        self.logsError = nil
                    } catch {
                        self.logsError = "Some saved entries could not be read. Comparison is unavailable until history can be loaded."
                        self.syncNotifications()
                        return
                    }
                    self.invalidateComparisonConversation()
                    self.syncNotifications() // predictions may have moved
                    self.prefetchAI()
                }
            },
            periodsRef.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error { self.periodsError = error.localizedDescription; self.syncNotifications(); return }
                    guard let snap, !snap.metadata.hasPendingWrites else { return }
                    do {
                        self.periodHistory = PeriodHistory(records: try snap.documents.map { try $0.data(as: PeriodRecord.self) })
                        self.periodsLoaded = true
                        self.periodsError = nil
                        self.invalidateComparisonConversation()
                        self.syncNotifications()
                        self.prefetchAI()
                    } catch { self.periodsError = "Some period history could not be read."; self.syncNotifications() }
                }
            },
            userRef.collection("reminders").order(by: "created", descending: true).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error { self.remindersError = error.localizedDescription; return }
                    guard let snap, !snap.metadata.hasPendingWrites else { return }
                    let docs = snap.documents
                    let legacy = docs.filter { $0.data()["kind"] == nil }.map(\.reference)
                    if !legacy.isEmpty {
                        self.remindersLoaded = false
                        self.replaceLegacyReminders(legacy, seedDefaults: legacy.count == docs.count)
                        return
                    }
                    do {
                        self.reminders = try docs.map { doc in
                            var reminder = try doc.data(as: Reminder.self)
                            reminder.id = doc.documentID
                            return reminder
                        }
                        self.remindersLoaded = true
                        self.remindersError = nil
                        self.syncNotifications()
                    } catch { self.remindersError = "Some reminders could not be read. Try again after reloading." }
                }
            },
            userRef.collection("predictions").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                MainActor.assumeIsolated {
                    guard let self, !self.forecastStopped, !self.deletingData else { return }
                    if let error {
                        print("Cycle forecast listener:", error)
                        self.forecasts = [:]
                        self.forecastMemory = nil
                        self.forecastsAvailable = false
                        self.syncNotifications()
                        return
                    }
                    guard let snap, !snap.metadata.hasPendingWrites else { return }
                    var forecasts: [String: AIForecast] = [:]
                    var memory: ForecastMemory?
                    for doc in snap.documents {
                        do {
                            if doc.documentID == "memory" {
                                let value = try doc.data(as: ForecastMemory.self)
                                memory = ForecastMemory(notes: Array(value.notes.prefix(5)).map { String($0.prefix(200)) },
                                                        basedOnCycles: min(100, max(0, value.basedOnCycles)))
                            } else {
                                let value = try doc.data(as: AIForecast.self)
                                if self.validStoredForecast(value, id: doc.documentID) { forecasts[doc.documentID] = value }
                            }
                        } catch { print("Could not read cycle forecast:", error) }
                    }
                    self.forecasts = forecasts
                    self.forecastMemory = memory
                    self.forecastsAvailable = true
                    self.syncNotifications()
                    self.prefetchAI()
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
        forecastStopped = true
        invalidateForecastRequest()
        loggingConversation.clear()
        reminderDeletion.clear()
        reminderClarification.clear()
        backfillTask?.cancel()
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

    func updateProfile(name: String, lastPeriodStart: Date, cycleLength: Int, periodLength: Int) async throws {
        let start = Self.cal.startOfDay(for: lastPeriodStart)
        let batch = db.batch()
        // Settings displays the latest recorded start, so edits must update that record too.
        if let latest = periodHistory.records.first,
           !Self.cal.isDate(start, inSameDayAs: latest.start) {
            if let periodStorageError {
                throw NSError(domain: "CycleStore", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: periodStorageError])
            }
            var next = periodHistory
            try next.save(id: latest.id, start: start, end: latest.end)
            guard let saved = next.records.first(where: { $0.id == latest.id }) else {
                throw PeriodHistory.Validation.missing
            }
            try batch.setData(from: saved, forDocument: periodsRef.document(saved.id.uuidString))
        }
        let baseline = CycleBaseline(lastStart: start, periodDays: periodLength, cycleDays: cycleLength)
        batch.updateData([
            "name": name,
            "lastPeriodStart": Timestamp(date: start),
            "cycleLength": cycleLength,
            "periodLength": periodLength,
            "baseline": try Firestore.Encoder().encode(baseline),
        ], forDocument: userRef)
        try await batch.commit()
        showToast("Settings saved")
    }

    /// Applies the palette immediately and saves it to the profile so other devices pick it up.
    func setPalette(_ theme: CoordinatedTheme) {
        PalettePreferences.shared.theme = theme
        guard profile != nil else { return } // No profile document until onboarding finishes.
        userRef.updateData(["palette": theme.rawValue]) { error in if let error { print("Palette update failed:", error) } }
    }

    /// Firestore is the source of truth; the local copy only covers launch until the profile loads,
    /// and resets to the default on sign-out. Profiles from before palettes were synced get this device's choice uploaded once.
    private func applySavedPalette() {
        guard let profile else { return }
        if let saved = profile.palette.flatMap(CoordinatedTheme.init(rawValue:)) {
            if PalettePreferences.shared.theme != saved { PalettePreferences.shared.theme = saved }
        } else {
            setPalette(PalettePreferences.shared.theme)
        }
    }

    /// Writes the profile plus a few default reminders the first time someone signs in.
    func completeOnboarding(name: String, lastPeriodStart: Date, cycleLength: Int, periodLength: Int, logHour: Int, logMinute: Int, periodDaysBefore: Int,
                            diets: Set<String>, avoid: Set<String>, dislikes: [String], aiConsent: Bool,
                            birthControl: BirthControl? = nil, birthControlReminders: [Reminder] = []) {
        let profile = Profile(name: name, lastPeriodStart: Self.cal.startOfDay(for: lastPeriodStart),
                              cycleLength: cycleLength, periodLength: periodLength,
                              diets: diets.sorted(), avoid: avoid.sorted(), dislikes: dislikes, aiConsent: aiConsent,
                              birthControl: birthControl)
        let batch = db.batch()
        _ = try? batch.setData(from: profile, forDocument: userRef)
        addDefaultReminders(to: batch, logHour: logHour, logMinute: logMinute, periodDaysBefore: periodDaysBefore,
                            mode: birthControl?.mode ?? .natural, first: birthControlReminders)
        batch.commit { error in if let error { print("Onboarding write failed:", error) } }
        ReminderNotifications.requestPermission()
    }

    /// `first` goes above the defaults, e.g. the pill reminder picked during onboarding.
    private func addDefaultReminders(to batch: WriteBatch, logHour: Int = 20, logMinute: Int = 30, periodDaysBefore: Int = 2,
                                     mode: CycleMode = .natural, first: [Reminder] = []) {
        let all = first + Reminder.defaults(logHour: logHour, logMinute: logMinute, periodDaysBefore: periodDaysBefore,
                                            bleed: mode != .natural, predicts: mode != .steady)
        for (i, var r) in all.enumerated() {
            r.created = Date().addingTimeInterval(-Double(i)) // keep this order under created-desc sorting
            _ = try? batch.setData(from: r, forDocument: userRef.collection("reminders").document(r.id))
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
        // Without predictions there's no window for "before period" reminders to count back from.
        ReminderNotifications.sync(reminders.filter { predictsBleeds || $0.kind != .beforePeriod },
                                   windowStart: windowStart, name: name, bleed: !tracksPhases)
    }

    // MARK: Cycle maths

    /// Saved bleeds, newest first, plus the onboarding/settings start date when it isn't saved as a record.
    /// Matches what the calendar shades, so summaries never disagree with it.
    var bleedRecords: [PeriodRecord] {
        var records = periodHistory.records
        if !periodHistory.contains(lastStart), lastStart <= today {
            records.append(PeriodRecord(start: lastStart, end: min(today, Self.add(lastStart, periodLength - 1))))
        }
        return records.sorted { $0.start > $1.start }
    }

    /// Calendar records include flow-created periods and retain explicit date corrections.
    var starts: [Date] {
        periodHistory.cycleStarts(fallback: profile?.lastPeriodStart ?? today)
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
    /// Uncertainty in days either side of the predicted start, never less than 2. A pack bleed is tighter.
    var spread: Int {
        if packBleedStart != nil { return 1 }
        return activeAIForecast?.spreadDays ?? baselineSpread
    }
    var nextStart: Date { packBleedStart ?? activeAIForecast.flatMap { LogDate.parse($0.predictedStart) } ?? baselineNextStart }
    var windowStart: Date { Self.add(nextStart, -spread) }
    var windowEnd: Date { Self.add(nextStart, spread) }
    var cycleDay: Int { Self.days(today, from: lastStart) + 1 }

    /// A phase can be absent when the cycle is too short for the usual offsets.
    /// Clamp derived boundaries only; never rewrite the user's saved lengths.
    nonisolated static func phaseRange(of phase: Phase, cycleLength: Int, periodLength: Int) -> ClosedRange<Int>? {
        let length = max(1, cycleLength)
        let bleedingEnd = min(length, max(1, periodLength))
        let follicularEnd = max(bleedingEnd, length - min(length, 16))
        let ovulationEnd = max(follicularEnd, length - min(length, 12))

        switch phase {
        case .menstrual:
            return 1...bleedingEnd
        case .follicular:
            guard follicularEnd > bleedingEnd else { return nil }
            return (bleedingEnd + 1)...follicularEnd
        case .ovulation:
            guard ovulationEnd > follicularEnd else { return nil }
            return (follicularEnd + 1)...ovulationEnd
        case .luteal:
            guard length > ovulationEnd else { return nil }
            return (ovulationEnd + 1)...length
        }
    }

    func range(of phase: Phase) -> ClosedRange<Int>? {
        Self.phaseRange(of: phase, cycleLength: average, periodLength: periodLength)
    }

    func phase(forDay day: Int) -> Phase {
        Phase.allCases.first { range(of: $0)?.contains(day) == true } ?? .luteal
    }
    var currentPhase: Phase { phase(forDay: cycleDay) }

    // MARK: Birth control

    var birthControl: BirthControl? { profile?.birthControl }
    var cycleMode: CycleMode { birthControl?.mode ?? .natural }
    /// Phases only mean something without hormonal birth control.
    var tracksPhases: Bool { cycleMode == .natural }
    /// Whether Sync predicts the next period or bleed at all.
    var predictsBleeds: Bool { cycleMode != .steady }
    /// "period" without hormonal birth control, "bleed" on it: hormonal bleeds aren't periods.
    var bleedName: String { tracksPhases ? "period" : "bleed" }
    /// `bleedName` for the start of a sentence or a title.
    var bleedTitle: String { tracksPhases ? "Period" : "Bleed" }

    /// Day 1–28 of the current pack, patch or ring cycle.
    var packDay: Int? {
        guard cycleMode == .pack, let start = birthControl?.packStart else { return nil }
        let length = BirthControl.packLength
        return ((Self.days(today, from: start) % length) + length) % length + 1
    }

    /// The next withdrawal bleed after today's pack day, from the break in the schedule.
    private var packBleedStart: Date? {
        guard let day = packDay, let active = birthControl?.activeDays else { return nil }
        let offset = day <= active ? active + 1 - day : BirthControl.packLength + active + 1 - day
        return Self.add(today, offset)
    }

    /// Nourish tabs: the four phases, or just bleed days and every day when birth control pauses them.
    var foodPhases: [Phase] { tracksPhases ? Phase.allCases : [.menstrual, .ovulation] }

    /// Which meal set fits today.
    var foodPhase: Phase {
        if tracksPhases { return currentPhase }
        return isPeriod(today) ? .menstrual : .ovulation
    }

    func foodName(_ phase: Phase) -> String {
        guard !tracksPhases else { return phase.name }
        return phase == .menstrual ? "Bleed days" : "Every day"
    }

    func foodTip(_ phase: Phase) -> String {
        guard !tracksPhases else { return phase.foodTip }
        return phase == .menstrual ? Phase.menstrual.foodTip : "Balanced plates, lots of veg, and stay hydrated."
    }

    func foodBlurb(_ phase: Phase) -> String {
        guard !tracksPhases else { return phase.blurb }
        return phase == .menstrual ? Phase.menstrual.blurb
            : "Everyday balanced eating: plenty of veg, protein and fibre, regular meals and enough water."
    }

    /// One line on where the user is, for the AI plan and companion.
    var cycleContext: String {
        guard let method = birthControl?.method, !tracksPhases else {
            return "Cycle day \(cycleDay), \(currentPhase.name.lowercased()) phase. \(currentPhase.blurb)"
        }
        let pack = packDay.map { " Pack day \($0) of \(BirthControl.packLength)." } ?? ""
        return "Uses \(method.name.lowercased()) birth control, so cycle phases don't apply.\(pack) \(foodBlurb(foodPhase))"
    }

    func saveBirthControl(_ value: BirthControl?) {
        let field: Any = (try? value.map { try Firestore.Encoder().encode($0) }) ?? FieldValue.delete()
        userRef.updateData(["birthControl": field]) { error in if let error { print("Birth control update failed:", error) } }
        showToast("Settings saved")
    }

    func isPeriod(_ date: Date) -> Bool {
        date <= today && (periodHistory.contains(date) || logs.contains { $0.flow != "None" && Self.cal.isDate($0.date, inSameDayAs: date) }
            || starts.contains { let x = Self.days(date, from: $0); return x >= 0 && x < periodLength })
    }
    func isPredicted(_ date: Date) -> Bool {
        guard predictsBleeds else { return false }
        let x = Self.days(date, from: nextStart); return x >= 0 && x < periodLength
    }
    func isMaybe(_ date: Date) -> Bool {
        predictsBleeds && !isPredicted(date) && date >= windowStart && date <= Self.add(windowEnd, periodLength - 1)
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
        let since = Self.add(today, -59)
        var counts: [String: Int] = [:]
        for log in logs where log.date >= since { for s in log.symptoms { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Preserve an explicit saved None; only suggest flow for a new calendar-marked entry.
    func flowForLog(on date: Date, saved: String? = nil) -> String {
        if let saved = saved ?? log(for: date)?.flow { return saved }
        return periodHistory.contains(date) ? "Light" : "None"
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
        guard !deletingData else { throw CancellationError() }
        if let backfillTask { await backfillTask.value }
        guard !deletingData else { throw CancellationError() }
        var next = periodHistory
        try next.recordFlow(on: log.date, flow: log.flow,
                            previousFlowDays: logs.filter { $0.id != log.id && $0.flow != "None" }.map(\.date),
                            periodLength: periodLength, today: today)
        let batch = db.batch()
        try batch.setData(from: log, forDocument: userRef.collection("logs").document(log.id))
        for record in next.records where !periodHistory.records.contains(record) {
            try batch.setData(from: record, forDocument: periodsRef.document(record.id.uuidString))
        }
        for record in periodHistory.records where !next.records.contains(where: { $0.id == record.id }) {
            batch.deleteDocument(periodsRef.document(record.id.uuidString))
        }
        try await batch.commit()
        periodHistory = next
        publishSavedLog(log)
    }

    /// Read/merge/write the server's current day atomically; do not replace it with a stale UI copy.
    func appendCompanionLog(_ patch: CompanionLogPatch) async throws -> DayLog {
        guard !deletingData else { throw CancellationError() }
        if let backfillTask { await backfillTask.value }
        guard !deletingData else { throw CancellationError() }
        let reference = userRef.collection("logs").document(Self.key(patch.date))
        let periods = periodsRef
        let previousHistory = periodHistory
        let previousFlowDays = logs.filter { $0.id != Self.key(patch.date) && $0.flow != "None" }.map(\.date)
        let length = periodLength
        let currentDay = Self.cal.startOfDay(for: Date())
        let result = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(reference)
                let existing = snapshot.exists ? try snapshot.data(as: DayLog.self) : nil
                let log = try patch.merged(with: existing, today: currentDay)
                var next = previousHistory
                // A symptom-only log must not implicitly end a period because default flow is None.
                if patch.flow != nil {
                    try next.recordFlow(on: log.date, flow: log.flow, previousFlowDays: previousFlowDays,
                                        periodLength: length, today: currentDay)
                }
                try transaction.setData(from: log, forDocument: reference)
                for record in next.records where !previousHistory.records.contains(record) {
                    try transaction.setData(from: record, forDocument: periods.document(record.id.uuidString))
                }
                for record in previousHistory.records where !next.records.contains(where: { $0.id == record.id }) {
                    transaction.deleteDocument(periods.document(record.id.uuidString))
                }
                return CompanionLogCommit(log: log, history: patch.flow == nil ? nil : next)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        guard let committed = result as? CompanionLogCommit else {
            throw NSError(domain: "PetalLog", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not verify the saved entry."])
        }
        if let history = committed.history { periodHistory = history }
        publishSavedLog(committed.log)
        return committed.log
    }

    private func publishSavedLog(_ log: DayLog) {
        logs.removeAll { $0.id == log.id }
        logs.append(log)
        logs.sort { $0.date > $1.date }
        invalidateComparisonConversation()
    }

    /// Saves a reminder and waits for Firestore, so the assistant only confirms real saves.
    func addReminder(_ reminder: Reminder) async throws {
        guard !deletingData else { throw CancellationError() }
        try await set(reminder, at: userRef.collection("reminders").document(reminder.id))
        publishReminder(reminder)
        ReminderNotifications.requestPermission()
    }

    func stageReminderClarification(_ request: String) {
        loggingConversation.clear()
        reminderClarification.stage(request)
    }

    func stageReminderDeletion(_ reminder: Reminder) {
        reminderClarification.clear()
        loggingConversation.clear()
        reminderDeletion.stage(id: reminder.id, title: reminder.title)
    }

    /// Atomically re-read server fields; edits never overwrite a stale whole reminder.
    func updateCompanionReminder(id: String, patch: ReminderPatch) async throws -> Reminder {
        guard !deletingData else { throw CancellationError() }
        let reference = userRef.collection("reminders").document(id)
        let currentDay = Self.cal.startOfDay(for: Date())
        try patch.validate(today: currentDay)
        let result = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(reference)
                guard snapshot.exists else { throw ContractError.invalid("This reminder no longer exists. List reminders again.") }
                var reminder = try snapshot.data(as: Reminder.self)
                reminder.id = id
                let fields = try patch.fields(for: reminder, today: currentDay)
                transaction.updateData(fields, forDocument: reference)
                // Decode the same merged fields for local state only after the commit acknowledges.
                var merged = (snapshot.data() ?? [:]).merging(fields) { _, new in new }
                // Firestore deletion sentinels are not decodable values in the local snapshot.
                if patch.schedule != nil { merged.removeValue(forKey: "weekdays") }
                let saved = try Firestore.Decoder().decode(Reminder.self, from: merged)
                return CompanionReminderCommit(reminder: saved)
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard let committed = result as? CompanionReminderCommit else { throw ContractError.invalid("Could not verify the reminder change.") }
        publishReminder(committed.reminder)
        if committed.reminder.on { ReminderNotifications.requestPermission() }
        return committed.reminder
    }

    private func deleteCompanionReminder(id: String, expectedTitle: String) async throws {
        guard !deletingData else { throw CancellationError() }
        let reference = userRef.collection("reminders").document(id)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(reference)
                guard snapshot.exists else { throw ContractError.invalid("The reminder no longer exists.") }
                let reminder = try snapshot.data(as: Reminder.self)
                guard reminder.title == expectedTitle else { throw ContractError.invalid("The reminder changed since confirmation. Please request deletion again.") }
                transaction.deleteDocument(reference)
                return true
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        reminders.removeAll { $0.id == id }
        syncNotifications()
    }

    private func publishReminder(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        reminders.sort { $0.created > $1.created }
        syncNotifications()
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

    private func visibleTags(builtins: [String], custom: [String], hidden: [String], order: [String]) -> [String] {
        var seen: Set<String> = []
        let available = (builtins + custom).filter { seen.insert($0).inserted }
        let visible = available.filter { !hidden.contains($0) }
        let ordered = order.filter { visible.contains($0) }
        return ordered + visible.filter { !ordered.contains($0) }
    }

    var allMoods: [String] {
        visibleTags(builtins: Self.moodOptions, custom: profile?.customMoods ?? [],
                    hidden: profile?.hiddenMoods ?? [], order: profile?.moodOrder ?? [])
    }
    var allSymptoms: [String] {
        visibleTags(builtins: Self.symptomOptions, custom: profile?.customSymptoms ?? [],
                    hidden: profile?.hiddenSymptoms ?? [], order: profile?.symptomOrder ?? [])
    }

    func emojiForTag(symptom: Bool, _ tag: String) -> String? {
        (symptom ? profile?.symptomEmojis : profile?.moodEmojis)?[tag]
    }

    /// Add, rename, or change the emoji of a mood/symptom. Existing day logs retain their historic labels.
    @discardableResult
    func saveEditableTag(symptom: Bool, original: String?, name: String, emoji: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 30, !emoji.isEmpty else { return nil }
        let tag = clean.prefix(1).uppercased() + clean.dropFirst()
        let current = symptom ? allSymptoms : allMoods
        guard !current.contains(where: { $0 != original && $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return nil }
        let builtins = symptom ? Self.symptomOptions : Self.moodOptions
        var custom = symptom ? (profile?.customSymptoms ?? []) : (profile?.customMoods ?? [])
        var hidden = symptom ? (profile?.hiddenSymptoms ?? []) : (profile?.hiddenMoods ?? [])
        var order = current
        var emojis = symptom ? (profile?.symptomEmojis ?? [:]) : (profile?.moodEmojis ?? [:])

        if let original, original != tag {
            if builtins.contains(original) && !hidden.contains(original) {
                hidden.append(original)
            } else {
                custom.removeAll { $0 == original }
            }
            order = order.map { $0 == original ? tag : $0 }
            emojis.removeValue(forKey: original)
        }
        if !builtins.contains(tag) && !custom.contains(tag) { custom.append(tag) }
        hidden.removeAll { $0 == tag } // Restore a previously removed built-in tag.
        if !order.contains(tag) { order.append(tag) }
        emojis[tag] = emoji

        userRef.updateData([
            symptom ? "customSymptoms" : "customMoods": custom,
            symptom ? "hiddenSymptoms" : "hiddenMoods": hidden,
            symptom ? "symptomOrder" : "moodOrder": order,
            symptom ? "symptomEmojis" : "moodEmojis": emojis,
        ])
        return tag
    }

    /// Hiding a built-in tag doesn't erase historic entries. Custom tags are removed from the menu.
    func removeTag(symptom: Bool, _ name: String) {
        let builtins = symptom ? Self.symptomOptions : Self.moodOptions
        var custom = symptom ? (profile?.customSymptoms ?? []) : (profile?.customMoods ?? [])
        var hidden = symptom ? (profile?.hiddenSymptoms ?? []) : (profile?.hiddenMoods ?? [])
        var order = symptom ? allSymptoms : allMoods
        var emojis = symptom ? (profile?.symptomEmojis ?? [:]) : (profile?.moodEmojis ?? [:])
        if builtins.contains(name) {
            if !hidden.contains(name) { hidden.append(name) }
        } else {
            custom.removeAll { $0 == name }
        }
        order.removeAll { $0 == name }
        emojis.removeValue(forKey: name)
        userRef.updateData([
            symptom ? "customSymptoms" : "customMoods": custom,
            symptom ? "hiddenSymptoms" : "hiddenMoods": hidden,
            symptom ? "symptomOrder" : "moodOrder": order,
            symptom ? "symptomEmojis" : "moodEmojis": emojis,
        ])
    }

    /// Move one visible tile before another and persist the ordering to Firebase.
    func moveTag(symptom: Bool, from source: String, to target: String) {
        guard source != target else { return }
        var ordered = symptom ? allSymptoms : allMoods
        guard let oldIndex = ordered.firstIndex(of: source), ordered.contains(target) else { return }
        ordered.remove(at: oldIndex)
        guard let newIndex = ordered.firstIndex(of: target) else { return }
        ordered.insert(source, at: newIndex)
        userRef.updateData([symptom ? "symptomOrder" : "moodOrder": ordered])
    }

    /// Keep the existing API for other code that may call it.
    @discardableResult
    func addCustom(symptom: Bool, _ name: String) -> String? {
        saveEditableTag(symptom: symptom, original: nil, name: name, emoji: symptom ? "🌀" : "😊")
    }
    func removeCustom(symptom: Bool, _ name: String) {
        removeTag(symptom: symptom, name)
    }

    func setAIConsent(_ on: Bool) {
        if !on {
            profile?.aiConsent = false
            invalidateForecastRequest()
            syncNotifications()
            plan = nil
            aiMeals = [:]
            messages = []
            assistant = nil
        }
        userRef.updateData(["aiConsent": on]) { error in
            if let error { Task { @MainActor in self.showToast("Couldn't update AI setting: \(error.localizedDescription)") } }
        }
    }

    func savePreferences(diets: Set<String>, avoid: Set<String>, dislikes: [String]) {
        userRef.updateData(["diets": diets.sorted(), "avoid": avoid.sorted(), "dislikes": dislikes]) { error in
            if let error { Task { @MainActor in self.showToast("Couldn't save preferences: \(error.localizedDescription)") } }
        }
    }

    /// Lowercase letters, spaces and hyphens only: dislikes end up in a cache document ID (see mealKey).
    static func cleanDislike(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0 == " " || $0 == "-" }.prefix(30))
            .trimmingCharacters(in: .whitespaces)
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
        deletingData = true
        invalidateForecastRequest()
        if let forecastTask { await forecastTask.value }
        defer { deletingData = false }
        backfillTask?.cancel()
        if let backfillTask { await backfillTask.value }
        let cached = try await cacheRef.getDocuments(source: .server).documents.map(\.reference)
        var refs = cached
        for collection in ["logs", "reminders", "grocery", "periods", "predictions"] {
            refs += try await userRef.collection(collection).getDocuments(source: .server).documents.map(\.reference)
        }
        refs.append(userRef)
        // Firestore batches are capped at 500 writes.
        for chunk in stride(from: 0, to: refs.count, by: 450).map({ refs[$0..<min($0 + 450, refs.count)] }) {
            let batch = db.batch()
            chunk.forEach { batch.deleteDocument($0) }
            try await batch.commit()
        }
        forecasts = [:]
        forecastMemory = nil
        forecastsAvailable = false
        forecastAttemptedHash = nil
        periodHistory = PeriodHistory()
        profile = nil
        logs = []
        reminders = []
        grocery = []
        periodStorageError = nil
        // Old PR versions used unscoped local keys. Never load them into an account;
        // remove the obsolete copies when the user explicitly deletes their data.
        for key in ["petal.periodHistory.v1", "petal.cycleBaseline.v1", "petal.loggedPeriodAdjustments.v1", backfillKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        aiMeals = [:]
        plan = nil
        messages = []
        loggingConversation.clear()
        reminderDeletion.clear()
        reminderClarification.clear()
        assistant = nil
        ReminderNotifications.sync([], windowStart: windowStart, name: name, bleed: false)
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
        .ovulation: [
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
            diets.allSatisfy(meal.diets.contains) && !meal.allergens.contains(where: avoid.contains) && !mentionsDislike(meal)
        }
    }

    private func mentionsDislike(_ meal: Meal) -> Bool {
        let text = ([meal.name] + meal.ingredients + meal.items).joined(separator: " ").lowercased()
        return dislikes.contains { text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))", options: .regularExpression) != nil }
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
        // Birth-control meal sets are prompted differently, so they're cached separately.
        (tracksPhases ? "" : "bc-") + "\(phase.rawValue)|\(diets.sorted().joined(separator: ","))|\(avoid.sorted().joined(separator: ","))"
            + (dislikes.isEmpty ? "" : "|" + dislikes.sorted().joined(separator: ","))
    }

    /// What Nourish shows: AI recipes once loaded, otherwise the built-in ideas.
    func shownMeals(for phase: Phase) -> [Meal] { (aiEnabled ? aiMeals[mealKey(phase)] : nil) ?? meals(for: phase) }

    func loadMeals(for phase: Phase, refresh: Bool = false) async {
        let key = mealKey(phase)
        guard aiEnabled, refresh || aiMeals[key] == nil, !mealsLoading.contains(key) else { return }
        mealsLoading.insert(key)
        mealsFailed.remove(key)
        defer { mealsLoading.remove(key) }
        let doc = cacheRef.document("meals-" + key)
        if !refresh, let cached = try? await doc.getDocument(as: CachedMeals.self),
           cached.created > Self.add(.now, -Self.mealCacheDays),
           cached.meals.count == 4, cached.meals.allSatisfy(Self.validMeal), !cached.meals.filter(fitsPreferences).isEmpty {
            aiMeals[key] = cached.meals.filter(fitsPreferences)
            return
        }
        do {
            let ideas = try await Assistant.mealIdeas(for: phase, focus: tracksPhases ? nil : (foodName(phase), foodBlurb(phase)), diets: diets, avoid: avoid, dislikes: dislikes, recentSymptoms: recentSymptoms,
                                                      notLike: aiMeals[key]?.map(\.name) ?? [])
            guard ideas.count == 4, ideas.allSatisfy(Self.validMeal) else { throw ContractError.invalid("Invalid recipe response.") }
            let safe = ideas.filter(fitsPreferences)
            if safe.isEmpty { throw CancellationError() }
            aiMeals[key] = safe
            if !deletingData, profile != nil {
                try? doc.setData(from: CachedMeals(meals: safe, created: .now))
            }
        } catch {
            print("Meal ideas failed:", error)
            mealsFailed.insert(key)
        }
    }

    static func validMeal(_ meal: Meal) -> Bool {
        CardValidation.meal(name: meal.name, why: meal.why, minutes: meal.minutes, servings: meal.servings,
            diets: meal.diets, allergens: meal.allergens, ingredients: meal.ingredients, shopping: meal.items, steps: meal.steps)
    }
    static func validPlan(_ items: [PlanItem]) -> Bool {
        items.count == 3 && items.allSatisfy { CardValidation.plan(icon: $0.icon, title: $0.title, detail: $0.detail) }
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
            "Date: \(today.formatted(.dateTime.weekday(.wide).month(.wide).day())). \(cycleContext)",
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
        guard aiEnabled, !planLoading else { return }
        planLoading = true
        defer { planLoading = false }
        let doc = cacheRef.document("plan")
        if let cached = try? await doc.getDocument(as: CachedPlan.self), cached.context == context, Self.validPlan(cached.items) {
            plan = cached.items
            return
        }
        do {
            let items = try await Assistant.dailyPlan(context: context)
            guard Self.validPlan(items), context == planContext else { return } // inputs changed mid-flight; the next call handles it
            plan = Array(items.prefix(3))
            if !deletingData, profile != nil {
                try? doc.setData(from: CachedPlan(items: Array(items.prefix(3)), context: context))
            }
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
        if let scheduledHash = forecastTaskHash, scheduledHash != currentForecastInputsHash {
            invalidateForecastRequest()
        }
        guard profile != nil, aiEnabled, !deletingData else { return }
        scheduleForecast()
        Task {
            await loadPlan()
            await loadMeals(for: foodPhase)
        }
    }

    /// Second check on AI recipes: the model's own labels, then a keyword scan of the ingredients.
    private func fitsPreferences(_ meal: Meal) -> Bool {
        guard diets.allSatisfy(meal.diets.contains), !meal.allergens.contains(where: avoid.contains), !mentionsDislike(meal) else { return false }
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
                _ = try? batch.setData(from: item, forDocument: userRef.collection("grocery").document(item.id))
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
        guard aiEnabled, !thinking else { return }
        today = Self.cal.startOfDay(for: Date())
        let previousAssistantText = messages.last(where: { !$0.fromUser })?.text
        messages.append(ChatMessage(fromUser: true, text: text))
        let pendingDeletionTitle = reminderDeletion.title
        if let id = reminderDeletion.consume(text) {
            loggingConversation.clear()
            thinking = true
            Task {
                defer { thinking = false }
                do {
                    try await deleteCompanionReminder(id: id, expectedTitle: pendingDeletionTitle ?? "")
                    ai("Your reminder “\(pendingDeletionTitle ?? "")” was deleted.")
                } catch { ai("Your reminder wasn't deleted. Please try again.") }
            }
            return
        }
        if pendingDeletionTitle != nil && ["no", "cancel", "never mind", "keep it"].contains(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            ai("Okay, your reminder has been kept.")
            return
        }
        let companionText = reminderClarification.consume(text, reminders: reminders) ?? text
        let authorization: LogAuthorization?
        switch loggingConversation.receive(companionText, now: today) {
        case .offer:
            ai("Would you like me to log “\(text)”? Nothing has been saved yet.")
            if Self.needsCare(text) { reply(to: text) }
            return
        case .dateRefined(let request):
            let date = request.resolvedDate?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? request.dateText ?? "that day"
            ai("Would you like me to log “\(request.text)” for \(date)? Nothing has been saved yet.")
            return
        case .authorized(let request): authorization = request
        case .clarify:
            ai("What would you like me to log, and for which day? Nothing has been saved yet.")
            return
        case .declined:
            ai("Okay, I won't log it. Nothing was saved.")
            return
        case .unrelated: authorization = nil
        }
        // Urgent symptoms get the fixed safety reply without waiting on the model.
        if authorization == nil && Self.needsCare(text) { return reply(to: text) }
        let conversation = Array(messages.dropLast().suffix(20))
        thinking = true
        Task {
            defer { thinking = false }
            do {
                let facts = "\(cycleDay)|\(windowStart)|\(windowEnd)|\(name)|\(historyRevision)"
                if assistant == nil || facts != assistantFacts {
                    assistant = Assistant(store: self, history: conversation)
                    assistantFacts = facts
                }
                let assistant = self.assistant!
                let isAffirmation = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    .range(of: #"^(yes|yeah|yep|sure|ok|okay)[,.! ]*(?:please)?[.!]?$"#, options: .regularExpression) != nil
                let response = try await assistant.reply(to: companionText, authorization: authorization,
                    immediateFollowUp: authorization == nil && isAffirmation ? previousAssistantText : nil,
                    conversation: conversation)
                if assistant.savedLogThisTurn != nil { loggingConversation.saved() }
                messages.append(ChatMessage(fromUser: false, text: response.text,
                    note: response.includesWellnessAdvice ? "AI-generated. Not medical advice." : nil,
                    comparisons: response.comparisons, recordedCycles: response.recordedCycles, savedLogs: response.savedLogs,
                    educationCitations: response.educationCitations, suggestedPrompts: response.suggestedPrompts))
            } catch {
                // No connection, billing not set up, etc.: fall back to the built-in replies.
                print("Assistant failed:", error)
                if authorization != nil {
                    ai("Nothing was saved. I couldn't process your logging request. Please try again.")
                } else if EducationLibrary.requiresEducation(text) || assistant?.educationRequested == true {
                    ai("I couldn’t verify an explanation right now. Please try again.")
                } else {
                    reply(to: text)
                }
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
            Task {
                do {
                    try await addReminder(Reminder(title: title, kind: .beforePeriod, hour: 9, minute: 0, daysBefore: 2))
                    ai("Your reminder is saved. You can switch it off under Reminders.")
                } catch { ai("Your reminder wasn't saved. Please try again.") }
            }
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
            let meal = meals(for: foodPhase).first ?? Self.meals[foodPhase]![0]
            ai((tracksPhases ? "You're in your \(currentPhase.name.lowercased()) phase. " : "") + "\(foodBlurb(foodPhase)) One idea that fits your preferences: \(meal.name).",
               note: "General nutrition ideas, not treatment.", actions: [.seeMeals])
        } else if has(["tired", "energy", "exhaust", "sleep"]) {
            ai("I couldn't verify an explanation right now. Please try again.")
        } else if has(["when", "next period", "late"]), !tracksPhases {
            ai(predictsBleeds
               ? "Your next bleed is expected around \(fmt(windowStart)) to \(fmt(windowEnd)), from your \(birthControl?.method.scheduleNoun ?? "pack") schedule. On hormonal birth control this is a withdrawal bleed, not a period."
               : "Bleeding can be irregular on your birth control, so I don't predict it. Logging any bleeding or spotting helps you spot patterns.",
               note: "Not for contraception or fertility planning.")
        } else if has(["when", "next period", "late"]) {
            ai("Your next period is most likely between \(fmt(windowStart)) and \(fmt(windowEnd)). Your cycles have ranged from \(pastLengths.min()!) to \(pastLengths.max()!) days, so I give a window instead of one date.",
               note: "Not for contraception or fertility planning.")
        } else {
            ai("I can help with reminders, food ideas for your cycle, self-care for period pain, or a summary of what you've logged. What would be most useful?")
        }
    }
}

/// NSObject allows the transaction result to cross the Firebase Objective-C completion boundary.
private final class CompanionLogCommit: NSObject {
    let log: DayLog
    let history: PeriodHistory?
    init(log: DayLog, history: PeriodHistory?) {
        self.log = log
        self.history = history
    }
}

private final class CompanionReminderCommit: NSObject {
    let reminder: Reminder
    init(reminder: Reminder) { self.reminder = reminder }
}

private extension ReminderPatch {
    func fields(for original: Reminder, today: Date) throws -> [String: Any] {
        let saved = try applying(to: original, today: today)
        var fields: [String: Any] = [:]
        if title != nil { fields["title"] = saved.title }
        if time != nil { fields["hour"] = saved.hour; fields["minute"] = saved.minute }
        if enabled != nil { fields["on"] = saved.on }
        if schedule != nil {
            fields["kind"] = saved.kind.rawValue
            fields["weekdays"] = FieldValue.delete()
        }
        if date != nil, let date = saved.date { fields["date"] = Timestamp(date: date) }
        if daysBefore != nil, let days = saved.daysBefore { fields["daysBefore"] = days }
        return fields
    }
}

// MARK: AI cycle forecast

extension CycleStore {
    var aiPredictionsEnabled: Bool { profile?.aiPredictions ?? true }

    var forecastScores: [ForecastScore] {
        Self.scoreForecasts(Array(forecasts.values), starts: starts)
    }

    var aiForecastEligible: Bool {
        ForecastEligibility(consent: aiEnabled, predictionsEnabled: aiPredictionsEnabled,
                            naturalCycle: tracksPhases, completedCycles: completedCycles.count,
                            dataReady: loaded && profile != nil && profileError == nil && logsLoaded && logsError == nil
                                && periodsLoaded && periodsError == nil,
                            predictionsReady: forecastsAvailable, deletingData: deletingData,
                            stopped: forecastStopped, benched: ForecastMath.isBenched(forecastScores)).allowed
    }

    var baselineNextStart: Date { Self.add(lastStart, average) }
    var baselineSpread: Int {
        let variance = pastLengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(pastLengths.count)
        return max(2, Int((sqrt(variance) * 1.5).rounded()))
    }

    private var forecastRelevantLogs: [DayLog] {
        logs.filter { log in
            (log.date >= lastStart && log.date <= today)
                || completedCycles.contains { log.date >= $0.start && log.date < Self.add($0.start, $0.length) }
        }
    }

    var currentForecastInputsHash: String {
        let scores = forecastScores.map { ForecastScoreInput(cycleStart: $0.cycleStart, predictedStart: $0.predictedStart,
            baselineStart: $0.baselineStart, actualStart: $0.actualStart, aiError: $0.aiError, mathError: $0.mathError) }
        return ForecastMath.inputsHash(lastStart: lastStart, cycles: completedCycles,
            periods: periodHistory.records.map { ($0.start, $0.end) }, logs: forecastRelevantLogs,
            average: average, spread: baselineSpread, configuredCycleLength: profile?.cycleLength ?? 28,
            configuredPeriodLength: profile?.periodLength ?? 5, referenceDate: today, scores: scores)
    }

    private var forecastEvidenceCycleStarts: Set<String> { Set(completedCycles.map { Self.key($0.start) }) }

    var activeAIForecast: AIForecast? {
        guard aiForecastEligible, let forecast = forecasts[Self.key(lastStart)],
              forecast.inputsHash == currentForecastInputsHash,
              forecast.baselineStart == Self.key(baselineNextStart), forecast.baselineSpread == baselineSpread,
              validStoredForecast(forecast, id: Self.key(lastStart)) else { return nil }
        return forecast
    }

    private func validStoredForecast(_ forecast: AIForecast, id: String) -> Bool {
        guard forecast.cycleStart == id, let start = LogDate.parse(id),
              let baseline = LogDate.parse(forecast.baselineStart), let predicted = LogDate.parse(forecast.predictedStart),
              (1...30).contains(forecast.baselineSpread), (-3...3).contains(forecast.shiftDays),
              (2...10).contains(forecast.spreadDays),
              forecast.spreadDays >= max(2, forecast.baselineSpread - 1),
              forecast.spreadDays <= min(10, forecast.baselineSpread + 3),
              Self.days(predicted, from: baseline) == forecast.shiftDays,
              (18...45).contains(Self.days(predicted, from: start)),
              !forecast.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              forecast.reason.count <= 200, forecast.model.count <= 60, forecast.inputsHash.count <= 128 else { return false }
        return true
    }

    /// Structured summaries only: never include a daily log's private note text.
    var forecastContext: String {
        var lines = ["Baseline: lastStart=\(Self.key(lastStart)); average=\(average); spread=\(baselineSpread); baselineStart=\(Self.key(baselineNextStart))."]
        for cycle in completedCycles.reversed() {
            let entries = logs.filter { $0.date >= cycle.start && $0.date < Self.add(cycle.start, cycle.length) }
            let periodLength = periodHistory.records.first { Self.key($0.start) == Self.key(cycle.start) }?.end
                .map { Self.days($0, from: cycle.start) + 1 }
            lines.append("Completed cycle (reference \(Self.key(cycle.start))): start=\(Self.key(cycle.start)); length=\(cycle.length); periodLength=\(periodLength.map(String.init) ?? "unknown"). \(ForecastMath.symptomSummary(entries))")
        }
        lines.append("Current cycle: day=\(cycleDay). \(ForecastMath.symptomSummary(logs.filter { $0.date >= lastStart && $0.date <= today }))")
        for score in forecastScores.reversed() {
            lines.append("Past forecast: cycleStart=\(score.cycleStart); predictedStart=\(score.predictedStart); baselineStart=\(score.baselineStart); actualStart=\(score.actualStart); aiError=\(score.aiError); mathError=\(score.mathError).")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func clampForecast(_ response: ForecastResponse, baselineStart: Date, baselineSpread: Int,
                                         lastStart: Date, allowedEvidence: Set<String>) -> (start: Date, spread: Int, reason: String, evidenceCycleStarts: [String])? {
        ForecastMath.clamp(response, baselineStart: baselineStart, baselineSpread: baselineSpread,
                           lastStart: lastStart, allowedEvidence: allowedEvidence)
    }

    nonisolated static func scoreForecasts(_ forecasts: [AIForecast], starts: [Date]) -> [ForecastScore] {
        ForecastMath.score(forecasts.map { ForecastHistoryEntry(cycleStart: $0.cycleStart, baselineStart: $0.baselineStart,
                                                              predictedStart: $0.predictedStart) }, starts: starts)
    }

    func setAIPredictions(_ on: Bool) {
        profile?.aiPredictions = on
        invalidateForecastRequest()
        syncNotifications()
        userRef.updateData(["aiPredictions": on]) { error in
            if let error { Task { @MainActor in self.showToast("Couldn't update AI predictions: \(error.localizedDescription)") } }
        }
        if on { prefetchAI() }
    }

    private func invalidateForecastRequest() {
        forecastGeneration += 1
        forecastTask?.cancel()
        forecastAttemptedHash = nil
        forecastFailureHash = nil
        forecastFailureCount = 0
    }

    func loadForecast() async {
        guard !Task.isCancelled, aiForecastEligible, !forecastLoading else { return }
        let id = Self.key(lastStart), hash = currentForecastInputsHash
        guard activeAIForecast == nil, forecastAttemptedHash != hash else { return }
        let generation = forecastGeneration, baseline = baselineNextStart, width = baselineSpread, cycleStart = lastStart
        let context = forecastContext
        forecastLoading = true
        forecastAttemptedHash = hash
        defer { forecastLoading = false }
        do {
            let request = ForecastRequest()
            let response = try await request.run { try await Assistant.cycleForecast(context: context) }
            try Task.checkCancellation()
            guard generation == forecastGeneration, id == Self.key(lastStart), hash == currentForecastInputsHash,
                  aiForecastEligible, !deletingData, profile != nil,
                  let clamped = Self.clampForecast(response, baselineStart: baseline, baselineSpread: width,
                                                   lastStart: cycleStart, allowedEvidence: forecastEvidenceCycleStarts) else { return }
            let forecast = AIForecast(cycleStart: id, baselineStart: Self.key(baseline), baselineSpread: width,
                                      shiftDays: Self.days(clamped.start, from: baseline), spreadDays: clamped.spread,
                                      predictedStart: Self.key(clamped.start), reason: clamped.reason,
                                      evidenceCycleStarts: clamped.evidenceCycleStarts,
                                      model: Assistant.fastModelName, inputsHash: hash)
            let batch = db.batch()
            try batch.setData(from: forecast, forDocument: userRef.collection("predictions").document(id))
            // Only the confirmed listener installs the result; denied/offline writes keep the math fallback.
            try await batch.commit()
            if hash == currentForecastInputsHash {
                forecastFailureHash = nil
                forecastFailureCount = 0
            }
        } catch {
            if !Task.isCancelled, generation == forecastGeneration, hash == currentForecastInputsHash, aiForecastEligible {
                if forecastFailureHash != hash { forecastFailureHash = hash; forecastFailureCount = 0 }
                forecastFailureCount += 1
                forecastAttemptedHash = ForecastRetryPolicy.delay(afterFailureCount: forecastFailureCount) == nil ? hash : nil
            }
            print("Cycle forecast failed:", error)
        }
    }

    private func scheduleForecast() {
        let hash = currentForecastInputsHash
        guard aiForecastEligible, !forecastLoading, forecastTaskID == nil,
              activeAIForecast == nil, forecastAttemptedHash != hash else { return }
        let taskID = UUID()
        forecastTaskID = taskID
        forecastTaskHash = hash
        forecastTask = Task { [weak self] in
            guard let self else { return }
            do {
                let delay = self.forecastFailureHash == hash
                    ? (ForecastRetryPolicy.delay(afterFailureCount: self.forecastFailureCount) ?? 0.25)
                    : 0.25
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
            } catch { }
            await self.loadForecast()
            guard self.forecastTaskID == taskID else { return }
            self.forecastTask = nil
            self.forecastTaskID = nil
            self.forecastTaskHash = nil
            // Re-check after a mid-flight edit or cancellation. Attempted inputs are deduplicated.
            self.scheduleForecast()
        }
    }
}
