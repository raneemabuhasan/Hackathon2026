import XCTest
@testable import PetalComparison

final class PeriodHistorySyncTests: XCTestCase {
    func testLegacyOnboardingStartAppearsWithoutInventingEndDate() {
        let start = Date(timeIntervalSince1970: 1_735_689_600)
        let history = PeriodHistory.restoring(records: nil, onboardingStart: start)
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records[0].start, Calendar.current.startOfDay(for: start))
        XCTAssertNil(history.records[0].end)
    }

    func testDeletedOnboardingPeriodDoesNotReturnAfterReload() {
        let start = Date(timeIntervalSince1970: 1_735_689_600)
        var history = PeriodHistory.restoring(records: nil, onboardingStart: start)
        history.remove(id: history.records[0].id)
        let restored = PeriodHistory.restoring(records: history.records, onboardingStart: start)
        XCTAssertTrue(restored.records.isEmpty)
    }

    func testEditedOnboardingPeriodKeepsIdentityWithoutRestoringOldStart() throws {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_735_689_600))
        var history = PeriodHistory.restoring(records: nil, onboardingStart: start)
        let recordID = history.records[0].id
        let corrected = Calendar.current.date(byAdding: .day, value: -1, to: start)!
        try history.save(id: recordID, start: corrected, end: nil)
        let restored = PeriodHistory.restoring(records: history.records, onboardingStart: start)
        XCTAssertEqual(restored.records.map(\.start), [corrected])
        XCTAssertEqual(restored.records[0].id, recordID)
    }
}
