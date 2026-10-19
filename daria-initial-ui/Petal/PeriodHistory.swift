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
