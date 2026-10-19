import XCTest
@testable import PetalComparison

final class PeriodLoggingTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/New_York")!
        return result
    }
    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: number))!
    }
    private func log(_ history: inout PeriodHistory, _ number: Int, flow: String = "Light",
                     previous: [Int] = [], today: Int = 20) throws {
        try history.recordFlow(on: day(number), flow: flow, previousFlowDays: previous.map(day),
                               periodLength: 5, today: day(today), calendar: calendar)
    }

    func testCorrectedStartTakesPriorityOverOldOnboardingDate() throws {
        var history = PeriodHistory()
        try history.save(start: day(15), end: day(19), today: day(20), calendar: calendar)
        XCTAssertEqual(history.cycleStarts(fallback: day(14), calendar: calendar), [day(15)])
        XCTAssertEqual(PeriodHistory().cycleStarts(fallback: day(14), calendar: calendar), [day(14)])
    }

    func testYesterdayFlowCanBeEndedTodayWithoutAnotherStart() throws {
        var history = PeriodHistory()
        try log(&history, 19)
        let period = try XCTUnwrap(history.periodToEnd(on: day(20), calendar: calendar))
        XCTAssertNil(period.end)
        try history.save(id: period.id, start: period.start, end: day(20), today: day(20), calendar: calendar)
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records[0].start, day(19))
        XCTAssertEqual(history.records[0].end, day(20))
    }

    func testCorrectionSurvivesRemovedSourceLogsAndReload() throws {
        var history = PeriodHistory()
        try log(&history, 18)
        let id = try XCTUnwrap(history.records.first?.id)
        try history.save(id: id, start: day(17), end: day(19), today: day(20), calendar: calendar)
        // The persisted record is independent of the daily-log collection. Reopening
        // with no source logs and editing a remaining entry must preserve the correction.
        var restored = try JSONDecoder().decode(PeriodHistory.self, from: JSONEncoder().encode(history))
        try log(&restored, 19, previous: [])
        XCTAssertEqual(restored.records, history.records)
        XCTAssertEqual(restored.records[0].id, id)
    }

    func testNoFlowEndsOngoingPeriodOnPriorDayAcrossDST() throws {
        var history = PeriodHistory()
        try log(&history, 7, today: 8)
        let id = history.records[0].id
        try log(&history, 8, flow: "None", previous: [7], today: 8)
        XCTAssertEqual(history.records[0].id, id)
        XCTAssertEqual(history.records[0].end, day(7))
    }

    func testNoFlowDoesNotOverwriteAnExplicitCompletedCorrection() throws {
        var history = PeriodHistory()
        try history.save(start: day(15), end: day(19), today: day(20), calendar: calendar)
        let original = history.records
        try log(&history, 17, flow: "None", previous: [15, 16])
        XCTAssertEqual(history.records, original)
    }

    func testNoFlowOnStartRemovesOnlyThatOngoingPeriod() throws {
        var history = PeriodHistory()
        try history.save(start: day(1), end: day(4), today: day(20), calendar: calendar)
        let previous = history.records
        try log(&history, 20)
        try log(&history, 20, flow: "None")
        XCTAssertEqual(history.records, previous)
    }

    func testTenDayFlowGapStartsNewPeriodWithStablePreviousID() throws {
        var history = PeriodHistory()
        try log(&history, 1, today: 1)
        let firstID = history.records[0].id
        try log(&history, 11, previous: [1], today: 11)
        XCTAssertEqual(history.records.count, 2)
        XCTAssertEqual(history.records[1].id, firstID)
        XCTAssertEqual(history.records[1].end, day(1))
        XCTAssertEqual(history.records[0].start, day(11))
        XCTAssertNil(history.records[0].end)
    }

    func testMissingDaysAloneDoNotCloseOngoingPeriod() throws {
        var history = PeriodHistory()
        try log(&history, 15, today: 15)
        try log(&history, 20, previous: [15])
        XCTAssertEqual(history.records.count, 1)
        XCTAssertNil(history.records[0].end)
    }

    func testHistoricalFlowDaysStayGroupedWithoutOverlappingLaterPeriod() throws {
        var history = PeriodHistory()
        try log(&history, 20)
        let currentID = history.records[0].id
        for n in 1...4 { try log(&history, n, previous: Array(1..<n)) }
        XCTAssertEqual(history.records.count, 2)
        XCTAssertEqual(history.records[0].id, currentID)
        XCTAssertNil(history.records[0].end)
        XCTAssertEqual(history.records[1].start, day(1))
        XCTAssertEqual(history.records[1].end, day(4))
    }

    func testFutureFlowIsRejectedWithoutChangingHistory() throws {
        var history = PeriodHistory()
        XCTAssertThrowsError(try log(&history, 21))
        XCTAssertTrue(history.records.isEmpty)
    }

    func testLaterNoFlowDoesNotInventWeeksOfBleeding() throws {
        var history = PeriodHistory()
        try log(&history, 1, today: 1)
        try log(&history, 20, flow: "None", previous: [1, 2])
        XCTAssertEqual(history.records[0].end, day(2))
    }
}
