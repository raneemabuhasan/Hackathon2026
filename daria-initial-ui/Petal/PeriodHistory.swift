import Foundation

struct PeriodRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date?
}

/// Date-only records shared by calendar controls and future logging integrations.
struct PeriodHistory: Codable {
    private(set) var records: [PeriodRecord]

    init(records: [PeriodRecord] = []) {
        self.records = records.sorted { $0.start > $1.start }
    }

    mutating func save(id: UUID? = nil, start: Date, end: Date?, today: Date = .now, calendar: Calendar = .current) throws {
        let start = calendar.startOfDay(for: start)
        let end = end.map { calendar.startOfDay(for: $0) }
        let today = calendar.startOfDay(for: today)
        guard start <= today, end.map({ $0 <= today }) ?? true else { throw Validation.future }
        guard end.map({ $0 >= start }) ?? true else { throw Validation.order }
        if let id, !records.contains(where: { $0.id == id }) { throw Validation.missing }
        let others = records.filter { $0.id != id }
        guard end != nil || !others.contains(where: { $0.end == nil }) else { throw Validation.active }
        let upper = end ?? .distantFuture
        guard !others.contains(where: { start <= ($0.end ?? .distantFuture) && $0.start <= upper }) else { throw Validation.overlap }
        records.removeAll { $0.id == id }
        records.append(PeriodRecord(id: id ?? UUID(), start: start, end: end))
        records.sort { $0.start > $1.start }
    }

    mutating func remove(id: UUID) { records.removeAll { $0.id == id } }

    /// Update durable calendar records from a daily entry. Editing or deleting a log later
    /// does not rebuild these records, so user-corrected dates retain their identity.
    mutating func recordFlow(on date: Date, flow: String, previousFlowDays: [Date],
                             periodLength: Int, today: Date = .now,
                             calendar: Calendar = .current) throws {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: today)
        guard day <= today else { throw Validation.future }
        func days(_ a: Date, from b: Date) -> Int {
            calendar.dateComponents([.day], from: b, to: a).day ?? 0
        }
        if flow == "None" {
            // A completed record is an explicit date correction; leave it intact.
            guard let active = records.first(where: { $0.end == nil && $0.start <= day }) else { return }
            if active.start == day {
                remove(id: active.id)
            } else {
                let lastFlow = previousFlowDays.map { calendar.startOfDay(for: $0) }
                    .filter { $0 >= active.start && $0 < day }.max()
                let priorDay = calendar.date(byAdding: .day, value: -1, to: day)!
                let end = lastFlow.map { days(day, from: $0) > 7 ? $0 : priorDay } ?? priorDay
                try save(id: active.id, start: active.start, end: end, today: today, calendar: calendar)
            }
            return
        }
        if contains(day, today: today, calendar: calendar) { return }
        if let active = records.first(where: { $0.end == nil && $0.start <= day }) {
            let lastFlow = previousFlowDays.map { calendar.startOfDay(for: $0) }
                .filter { $0 >= active.start && $0 < day }.max() ?? active.start
            if days(day, from: lastFlow) < 10 { return }
            try save(id: active.id, start: active.start, end: lastFlow, today: today, calendar: calendar)
        }
        if let previous = records.first(where: { record in
            record.end.map { $0 < day && days(day, from: $0) <= 2 } ?? false
        }) {
            try save(id: previous.id, start: previous.start, end: day, today: today, calendar: calendar)
            return
        }
        // Historical entries must not create an open record across a later period.
        let ongoing = !records.contains { $0.end == nil || $0.start > day }
            && days(today, from: day) < periodLength
        try save(start: day, end: ongoing ? nil : day, today: today, calendar: calendar)
    }

    func periodToEnd(on date: Date, calendar: Calendar = .current) -> PeriodRecord? {
        let day = calendar.startOfDay(for: date)
        return records.sorted { $0.start > $1.start }.first { calendar.startOfDay(for: $0.start) <= day }
    }

    /// Once records exist, their corrected starts take precedence over onboarding
    /// and the original flow logs. Estimates still have a baseline for new accounts.
    func cycleStarts(fallback: Date, calendar: Calendar = .current) -> [Date] {
        let starts = Set(records.map { calendar.startOfDay(for: $0.start) }).sorted(by: >)
        return starts.isEmpty ? [calendar.startOfDay(for: fallback)] : starts
    }

    // An unfinished record confirms its start only; never imply an end date.
    func contains(_ date: Date, today: Date = .now, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return records.contains { day >= calendar.startOfDay(for: $0.start) && day <= calendar.startOfDay(for: $0.end ?? $0.start) }
    }

    enum Validation: String, LocalizedError {
        case future = "Choose today or an earlier date."
        case order = "The end date must be on or after the start date."
        case active = "End your current period before starting another."
        case overlap = "These dates overlap another period. Edit that record instead."
        case missing = "This record no longer exists."
        var errorDescription: String? { rawValue }
    }
}

struct CycleBaseline: Codable {
    var lastStart: Date?
    var periodDays: Int
    var cycleDays: Int?
}

struct CycleForecast {
    let start: Date?
    let length: Int
    let sampleCount: Int
    let margin: Int

    init(baseline: CycleBaseline?, records: [PeriodRecord], calendar: Calendar = .current) {
        let dates = Array(Set((records.map(\.start) + [baseline?.lastStart].compactMap { $0 })
            .map { calendar.startOfDay(for: $0) })).sorted()
        let lengths = zip(dates, dates.dropFirst()).map {
            calendar.dateComponents([.day], from: $0, to: $1).day!
        }.suffix(6).sorted()
        sampleCount = lengths.count
        if lengths.isEmpty { length = baseline?.cycleDays ?? 28 }
        else { length = (lengths[(lengths.count - 1) / 2] + lengths[lengths.count / 2]) / 2 }
        start = dates.last
        // A provisional window, not a statistical confidence interval.
        let typicalLength = length
        margin = max(3, lengths.map { abs($0 - typicalLength) }.max() ?? 3)
    }

    func next(calendar: Calendar = .current) -> Date? {
        start.flatMap { calendar.date(byAdding: .day, value: length, to: $0) }
    }
}

/// Observed intervals between consecutive saved period starts, oldest first.
struct RecordedCycle: Identifiable {
    var id: Date { start }
    let start: Date
    let nextStart: Date
    let days: Int

    static func recent(from records: [PeriodRecord], calendar: Calendar = .current) -> [RecordedCycle] {
        let starts = Array(Set(records.map { calendar.startOfDay(for: $0.start) })).sorted()
        return Array(zip(starts, starts.dropFirst()).compactMap { start, next -> RecordedCycle? in
            guard let days = calendar.dateComponents([.day], from: start, to: next).day, days > 0 else { return nil }
            return RecordedCycle(start: start, nextStart: next, days: days)
        }.suffix(5))
    }
}
