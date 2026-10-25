import Foundation

/// Foundation-only validation shared by tools and regression checks.
enum CompanionIntent {
    static func explicitDeletion(_ text: String) -> Bool {
        let words = EducationLibrary.tokens(text)
        return !words.isDisjoint(with: ["delete", "remove", "erase"]) && !text.lowercased().contains("don't") && !text.lowercased().contains("do not")
    }
    static func reminderCreation(_ text: String) -> Bool {
        let q = text.lowercased()
        return !q.contains("don't") && !q.contains("do not") && (q.contains("remind me") || q.contains("add a reminder") || q.contains("set a reminder") || q.contains("create a reminder"))
    }
    static func reminderChange(_ text: String) -> Bool {
        let words = EducationLibrary.tokens(text)
        return !words.isDisjoint(with: ["make", "move", "change", "edit", "update", "stop", "pause", "disable", "enable", "turn", "reschedule", "rename"])
    }
}

struct ReminderPatch {
    var title: String?
    var time: String?
    var enabled: Bool?
    var schedule: String?
    var date: String?
    var daysBefore: Int?

    static func timeParts(_ text: String) -> (Int, Int)? {
        guard text.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
    func validate(today: Date) throws {
        guard title != nil || time != nil || enabled != nil || schedule != nil || date != nil || daysBefore != nil else { throw ContractError.invalid("Specify a requested change.") }
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 80 { throw ContractError.invalid("Use a title of 1–80 characters.") }
        if let time, Self.timeParts(time) == nil { throw ContractError.invalid("Time must be HH:mm in 24-hour time.") }
        if let schedule, !["daily", "once", "before_period"].contains(schedule) { throw ContractError.invalid("Unknown reminder schedule.") }
        if let date {
            guard let day = LogDate.parse(date), day >= Calendar.current.startOfDay(for: today) else { throw ContractError.invalid("Use a valid local date today or later.") }
        }
        if let daysBefore, !(1...7).contains(daysBefore) { throw ContractError.invalid("days_before must be 1–7.") }
    }
}

enum ContractError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Consent is app-owned and only the next affirmative message can consume it.
struct ReminderDeletionConsent {
    private(set) var id: String?
    private(set) var title: String?
    mutating func stage(id: String, title: String) { self.id = id; self.title = title }
    mutating func clear() { id = nil; title = nil }
    mutating func consume(_ text: String) -> String? {
        defer { clear() }
        guard text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^(yes|yeah|yep|sure|ok|okay|delete it)[,.! ]*(?:please)?[.!]?$"#, options: .regularExpression) != nil else { return nil }
        return id
    }
}

enum CardValidation {
    static let planIcons = ["leaf", "fork.knife", "cup.and.saucer", "drop", "heart", "moon", "bed.double", "figure.walk", "figure.yoga", "sun.max", "phone", "bag"]
    static func text(_ value: String, max: Int) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= max }
    static func strings(_ values: [String], count: ClosedRange<Int>, max: Int) -> Bool {
        count.contains(values.count) && values.allSatisfy { text($0, max: max) }
    }
    static func plan(icon: String, title: String, detail: String) -> Bool {
        planIcons.contains(icon) && text(title, max: 80) && title.split(whereSeparator: \.isWhitespace).count <= 6 && text(detail, max: 500)
    }
    static func meal(name: String, why: String, minutes: Int?, servings: Int?, diets: [String], allergens: [String], ingredients: [String], shopping: [String], steps: [String]) -> Bool {
        text(name, max: 100) && text(why, max: 500) && (1...45).contains(minutes ?? 0) && (1...12).contains(servings ?? 0)
        && Set(diets).isSubset(of: ["vegetarian", "vegan", "gluten-free", "dairy-free"])
        && Set(allergens).isSubset(of: ["nuts", "dairy", "gluten", "soy", "eggs", "fish", "sesame"])
        && strings(ingredients, count: 1...30, max: 200) && strings(shopping, count: 3...6, max: 100) && strings(steps, count: 3...6, max: 500)
    }
}

/// A reminder the user can switch on or off. Stored at users/{uid}/reminders/{id}.
struct Reminder: Identifiable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case daily, once, beforePeriod, everyWeeks

        var label: String {
            switch self {
            case .daily: "Every day"
            case .once: "Once"
            case .beforePeriod: "Before period"
            case .everyWeeks: "Weekly"
            }
        }
    }

    var id = UUID().uuidString
    var title: String
    var kind: Kind
    var hour: Int
    var minute: Int
    /// Day to fire for `.once`.
    var date: Date? = nil
    /// Days before the predicted window for `.beforePeriod`.
    var daysBefore: Int? = nil
    /// Repeat interval for `.everyWeeks`, counted from `date`, e.g. a patch change.
    var weeks: Int? = nil
    /// Optional weekdays for daily reminders: Calendar weekday values, Sunday = 1.
    /// nil retains the original every-day schedule for older reminders.
    var weekdays: [Int]? = nil

    var repeatWeekdays: [Int]? {
        weekdays.map { values in [2, 3, 4, 5, 6, 7, 1].filter { values.contains($0) } }
    }

    /// Calendar triggers shared by the existing notification scheduler and contract tests.
    var dailyNotificationComponents: [DateComponents] {
        guard kind == .daily else { return [] }
        if let weekdays = repeatWeekdays {
            return weekdays.map { DateComponents(hour: hour, minute: minute, weekday: $0) }
        }
        return [DateComponents(hour: hour, minute: minute)]
    }
    var on = true
    var created = Date()
    /// Opens with a greeting for the time of day and the user's name, e.g. "Good evening, Maya."
    /// Optional so older reminders still decode.
    var greets: Bool? = nil

    /// Suggested set for new accounts: the period heads-up and the daily check-in. Onboarding picks the log time and the period heads-up.
    /// On hormonal birth control the heads-up is about a bleed, and it's off when nothing is predicted.
    static func defaults(logHour: Int = 20, logMinute: Int = 30, periodDaysBefore: Int = 2,
                         bleed: Bool = false, predicts: Bool = true) -> [Reminder] {
        [
            Reminder(title: bleed ? "Bleed may start soon" : "Period may start soon", kind: .beforePeriod, hour: 9, minute: 0,
                     daysBefore: periodDaysBefore, on: predicts),
            Reminder(title: "Don't forget to log your symptoms today!", kind: .daily, hour: logHour, minute: logMinute, on: true, greets: true),
        ]
    }

}

extension ReminderPatch {
    func applying(to original: Reminder, today: Date) throws -> Reminder {
        try validate(today: today)
        var reminder = original
        if let title { reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let time, let (hour, minute) = Self.timeParts(time) { reminder.hour = hour; reminder.minute = minute }
        if let enabled { reminder.on = enabled }
        if let schedule {
            guard let kind = Reminder.Kind(rawValue: schedule == "before_period" ? "beforePeriod" : schedule) else { throw ContractError.invalid("Unknown schedule.") }
            reminder.kind = kind
            reminder.weekdays = nil
        }
        if reminder.kind == .once {
            guard let resolved = date.flatMap({ LogDate.parse($0) }) ?? reminder.date,
                  (!reminder.on || resolved >= today) else { throw ContractError.invalid("A one-off reminder needs a date today or later.") }
            if date != nil { reminder.date = resolved }
            if daysBefore != nil { throw ContractError.invalid("days_before requires before_period.") }
        } else if date != nil { throw ContractError.invalid("date requires a once schedule.") }
        if reminder.kind == .beforePeriod {
            guard let days = daysBefore ?? reminder.daysBefore, (1...7).contains(days) else { throw ContractError.invalid("Specify days_before (1–7) for this schedule.") }
            reminder.daysBefore = days
        } else if daysBefore != nil { throw ContractError.invalid("days_before requires before_period.") }
        return reminder
    }
}


/// Resolves ambiguous names before a model-selected ID can mutate a reminder.
enum ReminderSelection {
    static func allows(id: String, in reminders: [Reminder], request: String) -> Bool {
        let q = request.lowercased()
        let exact = reminders.filter { q.contains($0.title.lowercased()) }
        if !exact.isEmpty { return exact.count == 1 && exact[0].id == id }
        let noise: Set<String> = ["my", "me", "the", "a", "an", "to", "at", "for", "reminder", "reminders", "please", "move", "change", "edit", "update", "stop", "delete", "remove", "turn", "off", "on", "set"]
        let words = EducationLibrary.tokens(request).subtracting(noise)
        let scores = reminders.map { ($0.id, EducationLibrary.tokens($0.title).subtracting(noise).intersection(words).count) }
        let best = scores.map(\.1).max() ?? 0
        let matches = scores.filter { $0.1 == best }
        return best > 0 && matches.count == 1 && matches[0].0 == id
    }
}

/// A short name clarification can refine only the immediately pending reminder request.
/// Anything else clears it, so a later "sure" cannot resume an older edit or deletion.
struct ReminderClarification {
    private var request: String?
    mutating func stage(_ request: String) { self.request = request }
    mutating func clear() { request = nil }
    mutating func consume(_ answer: String, reminders: [Reminder]) -> String? {
        defer { clear() }
        guard let request else { return nil }
        let words = EducationLibrary.tokens(answer)
        let unrelated: Set<String> = ["yes", "sure", "okay", "ok", "no", "cancel", "why", "how", "what", "explain", "tell", "log", "save", "delete", "remove", "stop", "move", "change", "edit", "remind"]
        guard !answer.contains("?"), !words.isEmpty, words.count <= 8, words.isDisjoint(with: unrelated),
              reminders.contains(where: { ReminderSelection.allows(id: $0.id, in: reminders, request: answer) }) else { return nil }
        return request + "\nThe user clarified the intended reminder: " + answer
    }
}

/// Current-message requirements supplement the model's conversational routing.
/// History supplies context, but must not replace an explicit new request.
struct CompanionResponseFocus {
    let wantsMealIdeas: Bool

    init(message: String) {
        let words = EducationLibrary.tokens(message)
        let food: Set<String> = ["eat", "eating", "food", "foods", "meal", "meals", "snack", "snacks", "breakfast", "lunch", "dinner", "recipe", "recipes"]
        let historyOrAction: Set<String> = ["logged", "recorded", "ate", "log", "record", "save", "remind", "reminder"]
        let q = message.lowercased()
        let askingAboutHistory = ["what did", "what have i", "show my", "did i", "have i"].contains { q.contains($0) }
        let medicalClaim: Set<String> = ["cure", "cures", "treat", "treats", "balance", "balancing", "hormones", "allergy", "allergies", "cause", "causes", "evidence"]
        let requestWords: Set<String> = ["what", "which", "any", "suggest", "ideas", "recommend", "something", "should", "could", "can", "options", "help", "give", "want", "need"]
        wantsMealIdeas = !words.isDisjoint(with: food) && words.isDisjoint(with: historyOrAction)
            && !askingAboutHistory && words.isDisjoint(with: medicalClaim) && !words.isDisjoint(with: requestWords)
    }

    func accepts(_ answer: EducationAnswer, previousAnswer: String?) -> Bool {
        if answer.text == EducationEvidence.unsupported { return true }
        if wantsMealIdeas, let previousAnswer, Self.normalized(answer.text) == Self.normalized(previousAnswer) { return false }
        if wantsMealIdeas {
            let nutritionIDs: Set<String> = ["syncing-evidence", "nutrition-menstrual", "nutrition-other-phases"]
            return answer.citations.contains { nutritionIDs.contains($0.passageID) }
        }
        return true
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
