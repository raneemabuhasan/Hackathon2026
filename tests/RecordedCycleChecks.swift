import Foundation

@main
struct RecordedCycleChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 3, day: day))!
        }
        func record(_ day: Int) -> PeriodRecord { PeriodRecord(start: date(day), end: nil) }
        func cycles(_ records: [PeriodRecord]) -> [RecordedCycle] {
            RecordedCycle.recent(from: records, calendar: calendar)
        }
        assert(cycles([]).isEmpty)
        assert(cycles([record(1)]).isEmpty)
        let interval = cycles([record(10), record(7)])
        assert(interval.count == 1 && interval[0].days == 3) // Across DST.
        assert(interval[0].start == date(7) && interval[0].nextStart == date(10))
        assert(cycles([record(7), record(7), record(10)]).count == 1)
        let recent = cycles([1, 3, 7, 10, 15, 21, 28].map(record))
        assert(recent.map(\.days) == [4, 3, 5, 6, 7])
        assert(recent.first?.start == date(3))
        assert(cycles([record(1), record(10), record(28)]).map(\.days) == [9, 18])
        assert(cycles([record(1), record(28)]).map(\.days) == [27]) // Deleted middle start.
        assert(cycles([record(1), record(27)]).map(\.days) == [26]) // Edited start.
        print("PASS: empty/single start, DST, sorting, duplicate dates, latest five, deletion and editing")
    }
}
