import Foundation

@main
struct PeriodHistoryChecks {
    static func main() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: n))! }
        var history = PeriodHistory()
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Expected validation failure") }
            catch { assert(error is PeriodHistory.Validation) }
        }
        try history.save(start: day(7), end: nil, today: day(20), calendar: cal)
        let id = history.records[0].id
        assert(history.contains(day(7), today: day(20), calendar: cal))
        assert(!history.contains(day(8), today: day(20), calendar: cal))
        rejects { try history.save(start: day(9), end: nil, today: day(20), calendar: cal) }
        rejects { try history.save(id: id, start: day(7), end: day(6), today: day(20), calendar: cal) }
        rejects { try history.save(id: id, start: day(7), end: day(21), today: day(20), calendar: cal) }
        try history.save(id: id, start: day(7), end: day(9), today: day(20), calendar: cal)
        assert(history.contains(day(9), today: day(20), calendar: cal))
        assert(!history.contains(day(10), today: day(20), calendar: cal))
        rejects { try history.save(start: day(9), end: day(11), today: day(20), calendar: cal) }
        try history.save(start: day(15), end: day(15), today: day(20), calendar: cal)
        rejects { try history.save(id: id, start: day(7), end: nil, today: day(20), calendar: cal) }
        // Backfill a previous period with distinct selected calendar days.
        var backfill = PeriodHistory()
        try backfill.save(start: day(1), end: nil, today: day(20), calendar: cal)
        let backfillID = backfill.records[0].id
        try backfill.save(id: backfillID, start: day(1), end: day(5), today: day(20), calendar: cal)
        assert(backfill.records[0].start == day(1) && backfill.records[0].end == day(5))
        // Switching Ended off and back on preserves the start and record identity.
        try backfill.save(id: backfillID, start: day(1), end: nil, today: day(20), calendar: cal)
        assert(backfill.records[0].end == nil)
        try backfill.save(id: backfillID, start: day(1), end: day(6), today: day(20), calendar: cal)
        assert(backfill.records[0].id == backfillID && backfill.records[0].end == day(6))
        // No estimated duration: accept short, long, and corrected end dates.
        var flexible = PeriodHistory()
        try flexible.save(start: day(1), end: nil, today: day(31), calendar: cal)
        let flexibleID = flexible.records[0].id
        assert(!flexible.contains(day(7), today: day(31), calendar: cal))
        for lastDay in [2, 14, 28, 3] {
            try flexible.save(id: flexibleID, start: day(1), end: day(lastDay), today: day(31), calendar: cal)
            assert(flexible.records[0].end == day(lastDay))
            assert(flexible.contains(day(lastDay), today: day(31), calendar: cal))
            assert(!flexible.contains(day(lastDay + 1), today: day(31), calendar: cal))
        }
        try flexible.save(id: flexibleID, start: day(1), end: nil, today: day(31), calendar: cal)
        assert(flexible.contains(day(1), today: day(31), calendar: cal))
        assert(!flexible.contains(day(2), today: day(31), calendar: cal))
        let data = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(PeriodHistory.self, from: data)
        assert(restored.records == history.records)
        history.remove(id: id)
        assert(history.records.count == 1)
        // Backfill September while October is already saved and ongoing.
        func autumn(_ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
        var missed = PeriodHistory()
        let now = autumn(10, 18)
        try missed.save(start: autumn(10, 10), end: nil, today: now, calendar: cal)
        let ongoingID = missed.records[0].id
        try missed.save(start: autumn(9, 12), end: autumn(9, 17), today: now, calendar: cal)
        assert(missed.records.count == 2)
        assert(missed.records[0].id == ongoingID && missed.records[0].end == nil)
        assert(RecordedCycle.recent(from: missed.records, calendar: cal).map(\.days) == [28])
        let saved = missed.records
        rejects { try missed.save(start: autumn(9, 16), end: autumn(9, 20), today: now, calendar: cal) }
        rejects { try missed.save(start: autumn(9, 20), end: autumn(10, 10), today: now, calendar: cal) }
        assert(missed.records == saved) // Rejected overlaps never change saved records.
        try missed.save(start: autumn(8, 14), end: autumn(8, 14), today: now, calendar: cal)
        assert(missed.records.count == 3)
        print("PASS: unlimited duration, no inferred end, start/end, duplicate active record, invalid dates, inclusive boundaries across DST, overlap, editing, JSON round trip, deletion")
    }
}
