import Foundation

/// Snapshot of an existing database entry. No separate symptom store or document is created.
struct ComparisonEntry: Identifiable, Codable {
    var id = UUID().uuidString
    var date: Date
    var symptoms: [String] = []
    var pain: Int? = nil
    var note = ""

    static func databaseEntry(id: String, date: Date, symptoms: [String], pain: Int, note: String) -> ComparisonEntry {
        // Current database schema cannot distinguish default zero from an explicit zero.
        ComparisonEntry(id: id, date: date, symptoms: symptoms,
                        pain: (1...10).contains(pain) ? pain : nil, note: note)
    }
}

struct ComparedCycle: Identifiable, Codable {
    var id: Date { start }
    let start: Date
    let nextStart: Date?
    let logs: [ComparisonEntry]
    var isOngoing: Bool { nextStart == nil }
}

struct SymptomObservation: Identifiable, Codable {
    var id: String { symptom }
    let symptom: String
    let cyclesReported: Int
    let earlierDays: Int
    let laterDays: Int
    let evidence: [ComparisonEntry]
}

struct CycleComparison: Codable {
    let earlier: ComparedCycle
    let later: ComparedCycle
    let observations: [SymptomObservation]
    var earlierPeakPain: Int? { peakPain(earlier.logs) }
    var laterPeakPain: Int? { peakPain(later.logs) }
    private func peakPain(_ logs: [ComparisonEntry]) -> Int? {
        logs.compactMap(\.pain).filter { (0...10).contains($0) }.max()
    }
}

/// Pure comparison tool. No storage, network, AI inference, or medical thresholds.
enum SymptomComparisonEngine {
    static func cycles(starts: [Date], logs: [ComparisonEntry], asOf: Date,
                       calendar: Calendar = .current) -> [ComparedCycle] {
        let today = calendar.startOfDay(for: asOf)
        let dates = Set(starts.map { calendar.startOfDay(for: $0) })
            .filter { $0 <= today }.sorted()
        return dates.enumerated().map { index, start in
            let next = index + 1 < dates.count ? dates[index + 1] : nil
            let entries = logs.filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= start && day <= today && (next.map { day < $0 } ?? true)
            }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            return ComparedCycle(start: start, nextStart: next, logs: entries)
        }
    }

    static func compare(_ first: ComparedCycle, _ second: ComparedCycle,
                        calendar: Calendar = .current) -> CycleComparison? {
        guard first.start != second.start else { return nil }
        let earlier = first.start < second.start ? first : second
        let later = first.start < second.start ? second : first
        let names = Set((earlier.logs + later.logs).flatMap(\.symptoms)).sorted()
        let observations = names.map { name in
            let a = earlier.logs.filter { $0.symptoms.contains(name) }
            let b = later.logs.filter { $0.symptoms.contains(name) }
            let countDays: ([ComparisonEntry]) -> Int = { entries in
                Set(entries.map { calendar.startOfDay(for: $0.date) }).count
            }
            return SymptomObservation(symptom: name,
                cyclesReported: (a.isEmpty ? 0 : 1) + (b.isEmpty ? 0 : 1),
                earlierDays: countDays(a), laterDays: countDays(b), evidence: a + b)
        }
        return CycleComparison(earlier: earlier, later: later, observations: observations)
    }
}
