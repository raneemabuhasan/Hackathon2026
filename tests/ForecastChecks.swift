import Foundation
@main struct ForecastChecks {
 static func main() throws {
 // A saved cycle length takes effect while there's little history...
 assert(CycleLengthSelection.resolve(explicit: 35, recorded: [], fallback: 28) == 35)
 assert(CycleLengthSelection.resolve(explicit: 21, recorded: [28, 29], fallback: 35) == 21)
 // ...and three logged cycles take over, so logging keeps improving predictions.
 assert(CycleLengthSelection.resolve(explicit: 35, recorded: [28, 29, 27], fallback: 28) == 28)
 // Choosing an unknown length still allows history-based estimates and onboarding fallback.
 assert(CycleLengthSelection.resolve(explicit: nil, recorded: [28, 30], fallback: 35) == 29)
 assert(CycleLengthSelection.resolve(explicit: nil, recorded: [], fallback: 32) == 32)
 var cal = Calendar(identifier: .gregorian)
 cal.timeZone = TimeZone(identifier: "America/New_York")!
 let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 9))!
 let baseline = CycleBaseline(lastStart: start, periodDays: 6, cycleDays: nil)
 let f = CycleForecast(baseline: baseline, records: [], calendar: cal)
 assert(f.length == 28 && f.sampleCount == 0)
 assert(cal.component(.day, from: f.next(calendar: cal)!) == 6)
 assert(cal.component(.month, from: f.next(calendar: cal)!) == 11)
 assert(CycleForecast(baseline: nil, records: [], calendar: cal).next(calendar: cal) == nil)
 let custom = CycleForecast(baseline: CycleBaseline(lastStart: start, periodDays: 12, cycleDays: 35), records: [], calendar: cal)
 assert(custom.length == 35)
 let next = cal.date(byAdding: .day, value: 29, to: start)!
 let learned = CycleForecast(baseline: baseline, records: [PeriodRecord(start: start, end: nil), PeriodRecord(start: next, end: nil)], calendar: cal)
 assert(learned.sampleCount == 1 && learned.length == 29 && learned.start == next)
 let restored = try JSONDecoder().decode(CycleBaseline.self, from: JSONEncoder().encode(baseline))
 assert(restored.lastStart == start && restored.cycleDays == nil && restored.periodDays == 6)
 print("PASS: default/custom length, unknown start, calendar arithmetic across DST, deduplication, learned interval, baseline persistence")
 }
}
