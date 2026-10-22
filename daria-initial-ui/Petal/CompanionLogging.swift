import Foundation

struct DayLog: Identifiable, Codable, Equatable {
    var date: Date
    var flow = "None"
    var moods: [String] = []
    var symptoms: [String] = []
    var pain = 0
    var energy = 3
    var note = ""
    var id: String { LogDate.key(date) }
}

enum LogDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
    static func key(_ date: Date, calendar: Calendar = LogDate.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func parse(_ text: String, calendar: Calendar = LogDate.calendar) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              key(date, calendar: calendar) == text else { return nil }
        return calendar.startOfDay(for: date)
    }
}

struct LogAuthorization: Equatable {
    let text: String
    let referenceDate: Date
    var dateText: String? = nil
    var hasInvalidExplicitDate: Bool {
        for source in [text, dateText ?? ""] {
            guard let range = source.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) else { continue }
            if LogDate.parse(String(source[range])) == nil { return true }
        }
        return false
    }
    var resolvedDate: Date? {
        let q = (dateText ?? text).lowercased()
        let calendar = LogDate.calendar
        if let range = q.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) {
            return LogDate.parse(String(q[range]))
        }
        if let monthRange = q.range(of: #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?) \d{1,2}(?:,? \d{4})?\b"#, options: .regularExpression) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            let year = calendar.component(.year, from: referenceDate)
            let value = String(q[monthRange])
            for format in ["MMMM d, yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMM d yyyy"] {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: value) {
                    return calendar.startOfDay(for: parsed)
                }
                let withYear = "\(value), \(year)"
                formatter.dateFormat = format
                if let parsed = formatter.date(from: withYear) { return calendar.startOfDay(for: parsed) }
            }
            return nil
        }
        if let range = q.range(of: #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#, options: .regularExpression) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            for format in ["M/d/yyyy", "M/d/yy"] {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: String(q[range])) { return calendar.startOfDay(for: parsed) }
            }
            return nil
        }
        if q.contains("yesterday") { return calendar.date(byAdding: .day, value: -1, to: referenceDate) }
        if q.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: referenceDate) }
        if q.contains("today") { return referenceDate }
        for (index, name) in calendar.weekdaySymbols.enumerated() where q.contains(name.lowercased()) {
            var daysBack = (calendar.component(.weekday, from: referenceDate) - index - 1 + 7) % 7
            if q.contains("next ") {
                let daysForward = (index + 1 - calendar.component(.weekday, from: referenceDate) + 7) % 7
                return calendar.date(byAdding: .day, value: daysForward == 0 ? 7 : daysForward, to: referenceDate)
            }
            if q.contains("last ") { daysBack = daysBack == 0 ? 7 : daysBack + 7 }
            return calendar.date(byAdding: .day, value: -daysBack, to: referenceDate)
        }
        if calendar.monthSymbols.contains(where: { q.contains($0.lowercased()) })
            || q.range(of: #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#, options: .regularExpression) != nil { return nil }
        return referenceDate
    }
    var flow: String? {
        let q = text.lowercased()
        if q.range(of: #"\b(no bleeding|no flow|flow(?: is|:)? none)\b"#, options: .regularExpression) != nil { return "None" }
        for value in ["Light", "Medium", "Heavy"] {
            let word = value.lowercased()
            if q.range(of: "\\b(\(word) (flow|bleeding|period)|(flow|bleeding)( is|:)? \(word))\\b", options: .regularExpression) != nil {
                return value
            }
        }
        return nil
    }
    var context: String {
        "Authorized logging request: \(text)\(dateText.map { "\nDate clarification from the user: \($0)" } ?? "")\nResolve relative dates against \(LogDate.key(referenceDate)) in \(LogDate.calendar.timeZone.identifier). Use log_day now. Preserve the user's words and never infer a pain rating."
    }
    /// Only an explicit numeric pain rating can change the saved pain field.
    var painRating: Int? { numericPain.flatMap(Int.init) }
    var hasInvalidPainRating: Bool {
        guard numericPain != nil else { return false }
        return painRating.map { !(0...10).contains($0) } ?? true
    }
    private var numericPain: String? {
        let patterns = [#"\b([0-9]+(?:\.[0-9]+)?)\s*(?:/\s*10|out of 10)\b"#,
                        #"\bpain\s*(?:is|of|at|:|rating)?\s*([0-9]+(?:\.[0-9]+)?)\b"#]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let value = text as NSString
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: value.length)) {
                return value.substring(with: match.range(at: 1))
            }
        }
        return nil
    }
}

/// Consent belongs to the signed-in store, not the model chat that data refreshes can recreate.
struct LoggingConversation {
    private(set) var pending: LogAuthorization?
    enum Decision: Equatable { case offer, dateRefined(LogAuthorization), authorized(LogAuthorization), clarify, declined, unrelated }

    mutating func receive(_ text: String, now: Date) -> Decision {
        let q = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ pattern: String) -> Bool {
            q.range(of: pattern, options: .regularExpression) != nil
        }
        if matches(#"^(no\b|nope\b|cancel\b|don't\b|do not\b|never mind\b)"#) {
            let hadPending = pending != nil
            pending = nil
            let asksFollowUp = q.contains("?") || matches(#"\b(why|explain|how|tell me|what)\b"#)
            return hadPending && !asksFollowUp ? .declined : .unrelated
        }
        if matches(#"^(yes|yeah|yep|sure|ok|okay)[,.! ]*(?:(?:please )?(?:log|save|record|track|add) (?:it|that|this))?(?: please)?[.!]?$"#)
            || matches(#"^(please )?(log|save|record|track|add) (it|that|this)[.!]?$"#) {
            // A generic affirmation answers the immediately preceding companion turn when
            // there is no app-side logging consent. It must not trigger an old log prompt.
            guard let pending else { return .unrelated }
            return .authorized(pending)
        }
        if let pending, Self.isDateOnly(q) {
            var updated = pending
            updated.dateText = text
            self.pending = updated
            return .dateRefined(updated)
        }
        let command = matches(#"^(please |can you |could you |would you |i want to |i want you to |i'd like to |i would like to |yes,? )?(please )?(log|save|record|track|add|write down)\b"#)
            || matches(#"\b(?:can you|could you|would you|please) (?:please )?(log|save|record|track|add|write down)\b"#)
        if command {
            let request = LogAuthorization(text: text, referenceDate: now)
            pending = request
            return .authorized(request)
        }
        // Route questions to Gemini; don't interpret a question about symptoms as consent.
        let question = q.contains("?") || matches(#"^(what|why|how|when|which|can|does|do|show|compare|remind)\b"#)
        let feeling = matches(#"\b(i'm|i am|im|i feel|i have|i've been|my cramps|my head|my pain)\b"#)
            || matches(#"^(feeling|tired|exhausted|fatigued|cramps|headache|bloating)\b"#)
        let symptom = ["feel", "tired", "fatigue", "headache", "cramp", "bloat", "pain", "anxious", "sad", "happy", "bleed", "flow", "nause", "exhaust"]
            .contains { q.contains($0) }
        if !question && feeling && symptom {
            pending = LogAuthorization(text: text, referenceDate: now)
            return .offer
        }
        // A later bare "yes" must not authorize an old, unrelated offer.
        pending = nil
        return .unrelated
    }
    mutating func saved() { pending = nil }
    mutating func clear() { pending = nil }

    private static func isDateOnly(_ text: String) -> Bool {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
        return q.range(of: #"^(?:on )?(?:(?:this|last|next) )?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?: of (?:this|last|next) week)?[,.! ]*$"#, options: .regularExpression) != nil
            || q.range(of: #"^(?:on )?(?:today|yesterday|tomorrow|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{2,4}|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?) \d{1,2}(?:,? \d{4})?)[,.! ]*$"#, options: .regularExpression) != nil
    }
}

struct CompanionLogPatch {
    let date: Date
    var symptoms: [String] = []
    var moods: [String] = []
    var flow: String?
    var pain: Int?
    var note = ""

    enum Invalid: LocalizedError {
        case tag, date, fields, empty, wrongDay
        var errorDescription: String? {
            switch self {
            case .tag: return "Symptom and mood names must contain 1–30 characters."
            case .date: return "Choose a valid local date within the past year, not a future date."
            case .fields: return "Check flow, ratings, at most 20 tags per category, and note length (2000 characters)."
            case .empty: return "There is nothing to log."
            case .wrongDay: return "The existing entry has an inconsistent date; it was not overwritten."
            }
        }
    }

    /// Existing tags are valid values, not duplicate attempts to create a menu item.
    static func tag(_ input: String, known: [String]) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 30 else { throw Invalid.tag }
        return known.first { $0.caseInsensitiveCompare(value) == .orderedSame }
            ?? value.prefix(1).uppercased() + value.dropFirst()
    }

    func merged(with existing: DayLog?, today: Date, calendar: Calendar = LogDate.calendar) throws -> DayLog {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: today)
        guard day <= today, day >= calendar.date(byAdding: .day, value: -365, to: today)! else { throw Invalid.date }
        guard !symptoms.isEmpty || !moods.isEmpty || flow != nil || pain != nil || !note.isEmpty else { throw Invalid.empty }
        if let existing, !calendar.isDate(existing.date, inSameDayAs: day) { throw Invalid.wrongDay }
        var log = existing ?? DayLog(date: day)
        log.date = day
        for tag in symptoms where !log.symptoms.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { log.symptoms.append(tag) }
        for tag in moods where !log.moods.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { log.moods.append(tag) }
        if let flow { log.flow = flow }
        if let pain { log.pain = pain }
        if !note.isEmpty, !log.note.components(separatedBy: "\n").contains(note) {
            log.note = log.note.isEmpty ? note : log.note + "\n" + note
        }
        guard ["None", "Light", "Medium", "Heavy"].contains(log.flow), (0...10).contains(log.pain),
              (1...5).contains(log.energy), log.symptoms.count <= 20, log.moods.count <= 20, log.note.count <= 2000,
              (log.symptoms + log.moods).allSatisfy({ !$0.isEmpty && $0.count <= 30 }) else { throw Invalid.fields }
        return log
    }
}

/// Tracks actual execution, never the model's promises. The same runner is exercised with a fake writer in tests.
@MainActor
final class CompanionLogExecution {
    private(set) var attempted = false
    private(set) var saved: DayLog?
    private(set) var failure: String?

    func save(_ patch: CompanionLogPatch, writer: (CompanionLogPatch) async throws -> DayLog) async -> DayLog? {
        guard !attempted else { return saved }
        attempted = true
        do {
            let result = try await writer(patch)
            saved = result
            return result
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }
    func reject(_ message: String) { attempted = true; failure = message }
    var message: String {
        if let saved {
            return "Saved your entry for \(saved.date.formatted(.dateTime.month(.wide).day().year()))."
        }
        return "Nothing was saved. \(failure ?? "I couldn't complete the logging request. Please try again.")"
    }

    /// Defense in depth for unrecognized conversational phrasing, never a substitute for executing a write.
    nonisolated static func guardFalseSave(_ text: String) -> String {
        let q = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let pattern = #"\b(i've|i have|i'll|i will|i)\s+(?:just |already )?(?:log(?:ged)?\b|(?:sav(?:e|ed)|record(?:ed)?)\s+(?:that|it|this|your (?:entry|symptoms|mood|feelings|period)|the entry)\b)"#
        guard q.range(of: pattern, options: .regularExpression) != nil else { return text }
        return "I haven't saved an entry. Please tell me what you'd like to log and for which day."
    }
}
