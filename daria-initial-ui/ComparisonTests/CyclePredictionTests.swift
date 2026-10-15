import XCTest
@testable import PetalComparison

final class CyclePredictionTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    func day(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: Date(timeIntervalSince1970: 1_735_689_600))!
    }
    func predict(_ starts: [Int], asOf: Int = 500) -> PeriodPrediction? {
        CyclePredictionEngine.predict(starts: starts.map(day), asOf: day(asOf), calendar: calendar)
    }
    func testInsufficientHistoryIsNotFabricated() {
        XCTAssertNil(predict([]))
        XCTAssertNil(predict([0]))
        XCTAssertNil(predict([0, 28]))
    }
    func testRegularHistoryHasMinimumUncertainty() throws {
        let p = try XCTUnwrap(predict([0, 28, 56]))
        XCTAssertEqual(p.typicalLength, 28)
        XCTAssertEqual(p.windowStart, day(82))
        XCTAssertEqual(p.windowEnd, day(86))
    }
    func testVariationWidensWindowAndDoesNotDiscardLongGap() throws {
        let regular = try XCTUnwrap(predict([0, 28, 56]))
        let irregular = try XCTUnwrap(predict([0, 28, 88]))
        XCTAssertEqual(irregular.completedLengths, [28, 60])
        XCTAssertGreaterThan(irregular.windowEnd.timeIntervalSince(irregular.windowStart),
                             regular.windowEnd.timeIntervalSince(regular.windowStart))
    }
    func testSortDeduplicateAndIgnoreFutureStarts() throws {
        let p = try XCTUnwrap(predict([56, 0, 28, 28, 90], asOf: 60))
        XCTAssertEqual(p.completedLengths, [28, 28])
    }
    func testUsesLatestSixIntervals() throws {
        let p = try XCTUnwrap(predict([0, 10, 38, 66, 94, 122, 150, 178]))
        XCTAssertEqual(p.completedLengths, Array(repeating: 28, count: 6))
    }
    func testPassedWindowRemainsHistoricalEstimate() throws {
        let p = try XCTUnwrap(predict([0, 28, 56], asOf: 200))
        XCTAssertEqual(p.windowEnd, day(86))
        // UI displays neutral missing-start wording, rather than silently moving dates forward.
    }
}
