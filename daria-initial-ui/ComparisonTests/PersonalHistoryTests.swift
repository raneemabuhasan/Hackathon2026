import XCTest
@testable import PetalComparison

final class PersonalHistoryTests: XCTestCase {
    func testPersistenceAcrossRepositoryInstancesAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let repository = PersonalHistoryRepository(url: url)
        XCTAssertTrue(try repository.load().logs.isEmpty)
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let entry = DayLog(date: date, symptoms: ["Cramps"], pain: nil)
        var history = PersonalHistory(starts: [date], logs: [entry])
        history.periodEnds[date] = date.addingTimeInterval(86400)
        history.diets = ["vegetarian"]
        try repository.save(history)
        let reloaded = try PersonalHistoryRepository(url: url).load()
        XCTAssertEqual(reloaded.logs.first?.id, entry.id)
        XCTAssertEqual(reloaded.starts, [date])
        XCTAssertNil(reloaded.logs.first?.pain)
        XCTAssertEqual(reloaded.periodEnds[date], date.addingTimeInterval(86400))
        XCTAssertEqual(reloaded.diets, ["vegetarian"])
        history.logs.removeAll()
        try repository.save(history)
        XCTAssertTrue(try repository.load().logs.isEmpty)
        try repository.save(PersonalHistory())
        XCTAssertTrue(try repository.load().starts.isEmpty)
    }

    func testDailyReplacementPreservesIdentityAndReassignsDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let original = DayLog(date: date, symptoms: ["Cramps"])
        var history = PersonalHistory(logs: [original])
        history.save(DayLog(date: date.addingTimeInterval(3600), symptoms: ["Fatigue"], pain: 0), calendar: calendar)
        XCTAssertEqual(history.logs.count, 1)
        XCTAssertEqual(history.logs[0].id, original.id)
        XCTAssertEqual(history.logs[0].symptoms, ["Fatigue"])
        XCTAssertEqual(history.logs[0].pain, 0)
        var edited = history.logs[0]
        edited.date = date.addingTimeInterval(86400)
        history.save(edited, calendar: calendar)
        XCTAssertEqual(history.logs.count, 1)
        XCTAssertEqual(history.logs[0].date, edited.date)
    }

    func testCorruptHistoryThrowsWithoutReplacingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let corrupt = Data("invalid JSON".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try PersonalHistoryRepository(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testUnsupportedVersionDoesNotLoadAsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var history = PersonalHistory()
        history.version = 2
        let repository = PersonalHistoryRepository(url: url)
        try repository.save(history)
        XCTAssertThrowsError(try repository.load())
    }
}
