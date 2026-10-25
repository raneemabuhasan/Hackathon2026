import Foundation

/// Foundation-only validation shared by tools and regression checks.
enum CompanionIntent {
    static func isArithmeticQuestion(_ text: String) -> Bool {
        let number = #"(?:\d+(?:\.\d+)?|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|thirty(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|forty(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|fifty(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|sixty(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|seventy(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|eighty(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|ninety(?:\s+(?:one|two|three|four|five|six|seven|eight|nine))?|one\s+hundred)"#
        let operatorPattern = #"(?:\+|−|-|\*|×|÷|/|\bplus\b|\bminus\b|\btimes\b|\bdivided by\b|\bmultiplied by\b|\bx\b)"#
        let pattern = #"(?i)(?:\(\s*)?"# + number + #"\s*"# + operatorPattern + #"\s*"# + number + #"(?:\s*\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        // ISO dates are data, not arithmetic (e.g. a period logged on 2026-10-01).
        let datePatterns = [#"\b\d{4}-\d{2}-\d{2}\b"#, #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#, #"\b\d{4}/\d{1,2}/\d{1,2}\b"#]
        let withoutDates = datePatterns.reduce(text) { result, datePattern in
            result.replacingOccurrences(of: datePattern, with: " ", options: .regularExpression)
        }
        let range = NSRange(withoutDates.startIndex..<withoutDates.endIndex, in: withoutDates)
        return regex.firstMatch(in: withoutDates, range: range) != nil
    }

    static func isSupportedCompanionRequest(_ text: String) -> Bool {
        let words = EducationLibrary.tokens(text)
        let supported: Set<String> = [
            "period", "menstruation", "menstrual", "cycle", "bleed", "spotting", "pms", "phase", "ovulation", "cramp", "cramps",
            "symptom", "symptoms", "pain", "mood", "energy", "fatigue", "tired", "headache", "nausea",
            "acne", "bloating", "breast", "wellbeing", "wellness", "relief", "sleep", "stress", "log", "logged", "logging",
            "record", "recorded", "save", "saved", "history", "entry", "entries", "remind", "reminder",
            "reminders", "nutrition", "food", "foods", "eat", "eating", "meal", "meals", "snack", "recipe",
            "diet", "allergy", "allergies", "allergen", "cycleday", "birth", "control", "pill"
        ]
        return !words.isDisjoint(with: supported)
    }

    static func isSupportedFollowUp(_ text: String, previousUserRequest: String?) -> Bool {
        guard let previousUserRequest, isSupportedCompanionRequest(previousUserRequest), !isArithmeticQuestion(text) else { return false }
        let words = EducationLibrary.tokens(text)
        let followUps: Set<String> = ["why", "how", "what", "when", "which", "more", "explain", "that", "it", "then", "food", "eat", "doctor", "clinician"]
        return words.count <= 6 && !words.isDisjoint(with: followUps)
    }

    static func companionScope(_ text: String, previousUserRequest: String? = nil) -> CompanionRequestScope {
        if isArithmeticQuestion(text) { return .redirect }
        if containsExplicitUnrelatedRequest(text) { return .redirect }
        if isSupportedCompanionRequest(text) || isSupportedFollowUp(text, previousUserRequest: previousUserRequest) { return .inScope }
        let wordCount = EducationLibrary.tokens(text).count
        return wordCount <= 2 ? .clarify : .redirect
    }

    static func containsExplicitUnrelatedRequest(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let unrelated = ["write code", "write a poem", "tell me a joke", "weather today", "stock price", "capital of", "translate this", "generate an image", "write a function"]
        let unrelatedTerms: Set<String> = ["code", "coding", "program", "programming", "python", "javascript", "swift", "java", "weather", "stocks", "stock", "translate", "translation", "poem", "poetry", "joke", "image", "images"]
        return unrelated.contains(where: lowered.contains) || !EducationLibrary.tokens(text).isDisjoint(with: unrelatedTerms)
    }

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

enum CompanionRequestScope: Equatable {
    case inScope
    case clarify
    case redirect
}

enum CompanionAnswerSafety {
    static func hasUnsupportedClaim(_ text: String) -> Bool {
        let patterns = [
            #"(?i)\b(?:you (?:have|may have|might have|probably have|likely have|are experiencing)|this (?:means|shows) you have|your symptoms suggest)\s+(?:possible\s+)?(?:pcos|endometriosis|fibroids|thyroid disease|anemia|anaemia|a hormonal disorder)\b"#,
            #"(?i)\b(?:you are|you're|you will be|you'll be|you remain|you’re)\s+(?:still\s+)?protected\b|\b(?:you won't|you will not|you can’t|you cannot) get pregnant\b|\bsafe to have sex\b"#,
            #"(?i)\b(?:take|start taking|stop taking|double|increase|decrease)\s+(?:your\s+)?(?:pill|medication|medicine|dose|dosage|contraceptive|birth control|ibuprofen|aspirin|hormone)\b"#,
            #"(?i)\b(?:food|foods|diet|eating|supplements?)\s+(?:can|will|may|does)\s+(?:cure|treat|fix|prevent|balance hormones|regulate hormones|reduce bleeding|stop bleeding)\b"#,
            #"(?i)\b(?:this|these)\s+(?:food|foods|supplements?|meals?)\s+(?:cure|treat|fix|prevent|balance hormones|regulate hormones)\b"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    static func hasUnverifiedPersonalFacts(_ answer: String, evidence: String) -> Bool {
        var dates = answer.matches(#"\b\d{4}-\d{2}-\d{2}\b"#)
        let namedDatePattern = #"(?i)\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},\s+\d{4}\b"#
        for namedDate in answer.matches(namedDatePattern) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = LogDate.calendar.timeZone
            formatter.dateFormat = "MMMM d, yyyy"
            formatter.isLenient = false
            if let date = formatter.date(from: namedDate) { dates.append(LogDate.key(date)) }
            else { return true }
        }
        if dates.contains(where: { !evidence.contains($0) }) { return true }
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b(?:you|your)\b[^.!?\n]{0,60}\b(\d{1,3})\s+(?:day|days|week|weeks|cycle|cycles|entries|logs)\b"#) else { return false }
        let range = NSRange(answer.startIndex..<answer.endIndex, in: answer)
        return regex.matches(in: answer, range: range).contains { match in
            guard let valueRange = Range(match.range(at: 1), in: answer) else { return true }
            let value = NSRegularExpression.escapedPattern(for: String(answer[valueRange]))
            return evidence.range(of: #"\b"# + value + #"\b"#, options: .regularExpression) == nil
        }
    }
}

private extension String {
    func matches(_ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { Range($0.range, in: self).map { String(self[$0]) } }
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

    /// Suggested set for new accounts, most important first. Onboarding picks the log time and the period heads-up.
    /// On hormonal birth control the heads-up is about a bleed, and it's off when nothing is predicted.
    static func defaults(logHour: Int = 20, logMinute: Int = 30, periodDaysBefore: Int = 2,
                         bleed: Bool = false, predicts: Bool = true) -> [Reminder] {
        [
            Reminder(title: bleed ? "Bleed may start soon" : "Period may start soon", kind: .beforePeriod, hour: 9, minute: 0,
                     daysBefore: periodDaysBefore, on: predicts),
            Reminder(title: "Don't forget to log your symptoms today!", kind: .daily, hour: logHour, minute: logMinute, on: true, greets: true),
            Reminder(title: "Restock pads & tampons", kind: .beforePeriod, hour: 18, minute: 0, daysBefore: 5, on: false),
            Reminder(title: "Drink some water", kind: .daily, hour: 14, minute: 0, on: false),
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
