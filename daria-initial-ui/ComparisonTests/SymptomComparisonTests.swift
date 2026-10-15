import XCTest
@testable import PetalComparison

final class SymptomComparisonTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_735_689_600))!
    }
    func cycles(_ logs: [DayLog], starts: [Date]? = nil) -> [ComparedCycle] {
        SymptomComparisonEngine.cycles(starts: starts ?? [day(0), day(28)], logs: logs,
                                      asOf: day(40), calendar: calendar)
    }
    func testStartBoundaryAndUnknownDates() {
        let before = DayLog(date: day(-1), symptoms: ["Cramps"])
        let boundary = DayLog(date: day(28), symptoms: ["Cramps"])
        let future = DayLog(date: day(41), symptoms: ["Cramps"])
        let result = cycles([before, boundary, future], starts: [day(28), day(0), day(0), day(50)])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].logs.isEmpty)
        XCTAssertEqual(result[1].logs.map(\.id), [boundary.id])
        XCTAssertTrue(result[1].isOngoing)
    }
    func testMultipleEntriesAndDuplicateTagsCountUniqueLocalDays() throws {
        let logs = [DayLog(date: day(0), symptoms: ["Cramps", "Cramps"]),
                    DayLog(date: day(0).addingTimeInterval(3600), symptoms: ["Cramps"]),
                    DayLog(date: day(28), symptoms: ["Cramps"])]
        let c = cycles(logs)
        let result = try XCTUnwrap(SymptomComparisonEngine.compare(c[1], c[0], calendar: calendar))
        XCTAssertEqual(result.observations[0].earlierDays, 1)
        XCTAssertEqual(result.observations[0].laterDays, 1)
        XCTAssertEqual(result.observations[0].cyclesReported, 2)
        XCTAssertEqual(Set(result.observations[0].evidence.map(\.id)), Set(logs.map(\.id)))
    }
    func testMissingSymptomsAndPainRemainUnspecified() throws {
        let c = cycles([DayLog(date: day(0), symptoms: ["Fatigue"])])
        let r = try XCTUnwrap(SymptomComparisonEngine.compare(c[0], c[1]))
        XCTAssertEqual(r.observations[0].cyclesReported, 1)
        XCTAssertEqual(r.observations[0].laterDays, 0)
        XCTAssertNil(r.earlierPeakPain)
        XCTAssertNil(r.laterPeakPain)
    }
    func testExplicitZeroIsReportedAndInvalidPainExcluded() throws {
        let c = cycles([DayLog(date: day(0), pain: 0), DayLog(date: day(1), pain: 99),
                        DayLog(date: day(28), pain: 7)])
        let r = try XCTUnwrap(SymptomComparisonEngine.compare(c[0], c[1]))
        XCTAssertEqual(r.earlierPeakPain, 0)
        XCTAssertEqual(r.laterPeakPain, 7)
        XCTAssertTrue(r.observations.isEmpty)
    }
    func testEditAndDeletionRecomputeEvidence() throws {
        var logs = [DayLog(date: day(0), symptoms: ["Cramps"], pain: 4),
                    DayLog(date: day(28), symptoms: ["Cramps"], pain: 7)]
        let retainedID = logs[1].id
        logs[1].symptoms = ["Headache"]
        logs[1].pain = nil
        var c = cycles(logs)
        var r = try XCTUnwrap(SymptomComparisonEngine.compare(c[0], c[1]))
        XCTAssertEqual(r.observations.first { $0.symptom == "Cramps" }?.cyclesReported, 1)
        XCTAssertEqual(r.observations.first { $0.symptom == "Headache" }?.evidence.first?.id, retainedID)
        logs.removeLast()
        c = cycles(logs)
        r = try XCTUnwrap(SymptomComparisonEngine.compare(c[0], c[1]))
        XCTAssertFalse(r.observations.flatMap(\.evidence).contains { $0.id == retainedID })
        XCTAssertNil(r.laterPeakPain)
    }
    func testInsufficientAndSameCycle() {
        XCTAssertTrue(cycles([], starts: []).isEmpty)
        let c = cycles([], starts: [day(0)])
        XCTAssertNil(SymptomComparisonEngine.compare(c[0], c[0]))
    }
    func testLocalCalendarDeterminesCycleBoundary() {
        var local = calendar
        local.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let start = day(28).addingTimeInterval(5 * 3600)
        let entry = DayLog(date: start.addingTimeInterval(-3600), symptoms: ["Cramps"])
        let c = SymptomComparisonEngine.cycles(starts: [day(0), start], logs: [entry], asOf: day(40), calendar: local)
        XCTAssertEqual(c[0].logs.map(\.id), [entry.id])
        XCTAssertTrue(c[1].logs.isEmpty)
    }
    func testFixtureAndCodableToolOutput() throws {
        let starts = [day(0), day(28), day(59)]
        let logs = ComparisonMockData.logs(starts: starts, calendar: calendar)
        let c = SymptomComparisonEngine.cycles(starts: starts, logs: logs, asOf: day(70), calendar: calendar)
        let r = try XCTUnwrap(SymptomComparisonEngine.compare(c[1], c[2], calendar: calendar))
        XCTAssertEqual(r.earlierPeakPain, 5)
        XCTAssertEqual(r.laterPeakPain, 7)
        XCTAssertEqual(r.observations.first { $0.symptom == "Cramps" }?.cyclesReported, 2)
        let decoded = try JSONDecoder().decode(CycleComparison.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded.observations.flatMap(\.evidence).map(\.id), r.observations.flatMap(\.evidence).map(\.id))
    }
}
