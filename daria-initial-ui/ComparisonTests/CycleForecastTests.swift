import XCTest
@testable import PetalComparison

final class CycleForecastTests: XCTestCase {
    private func day(_ key: String) -> Date { LogDate.parse(key)! }
    private func response(shift: Int = 0, spread: Int = 3, reason: String = "A little longer.", notes: [String] = []) -> ForecastResponse {
        ForecastResponse(shiftDays: shift, spreadDays: spread, reason: reason, notes: notes)
    }

    func testEligibilityRequiresEveryGate() {
        let eligible = ForecastEligibility(consent: true, predictionsEnabled: true, naturalCycle: true,
                                          completedCycles: 3, dataReady: true, predictionsReady: true,
                                          deletingData: false, stopped: false, benched: false)
        XCTAssertTrue(eligible.allowed)
        let offGates: [WritableKeyPath<ForecastEligibility, Bool>] = [\.consent, \.predictionsEnabled, \.naturalCycle, \.dataReady, \.predictionsReady]
        for gate in offGates {
            var state = eligible; state[keyPath: gate] = false
            XCTAssertFalse(state.allowed)
        }
        let onGates: [WritableKeyPath<ForecastEligibility, Bool>] = [\.deletingData, \.stopped, \.benched]
        for gate in onGates {
            var state = eligible; state[keyPath: gate] = true
            XCTAssertFalse(state.allowed)
        }
        var shortHistory = eligible; shortHistory.completedCycles = 2
        XCTAssertFalse(shortHistory.allowed)
    }

    func testClampsShiftAndWindowAgainstBaseline() throws {
        let result = try XCTUnwrap(ForecastMath.clamp(response(shift: 99, spread: 99), baselineStart: day("2026-10-29"), baselineSpread: 3, lastStart: day("2026-10-01")))
        XCTAssertEqual(LogDate.key(result.start), "2026-11-01")
        XCTAssertEqual(result.spread, 6)
        let narrow = try XCTUnwrap(ForecastMath.clamp(response(shift: -99, spread: -99), baselineStart: day("2026-10-29"), baselineSpread: 4, lastStart: day("2026-10-01")))
        XCTAssertEqual(LogDate.key(narrow.start), "2026-10-26")
        XCTAssertEqual(narrow.spread, 3)
    }

    func testRejectsUnsafeCycleAndImpossibleWindow() {
        XCTAssertNil(ForecastMath.clamp(response(shift: -3), baselineStart: day("2026-10-19"), baselineSpread: 2, lastStart: day("2026-10-01")))
        XCTAssertNil(ForecastMath.clamp(response(shift: 3), baselineStart: day("2026-11-15"), baselineSpread: 2, lastStart: day("2026-10-01")))
        XCTAssertNil(ForecastMath.clamp(response(), baselineStart: day("2026-10-29"), baselineSpread: 12, lastStart: day("2026-10-01")))
        XCTAssertNil(ForecastMath.clamp(response(reason: " \n "), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01")))
    }

    func testTrimsBoundsAndDropsEmptyMemory() throws {
        let result = try XCTUnwrap(ForecastMath.clamp(response(reason: " \n" + String(repeating: "🌸", count: 210), notes: [" ", " first "] + Array(repeating: String(repeating: "x", count: 210), count: 7)), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01")))
        XCTAssertEqual(result.reason.count, 200)
        XCTAssertEqual(result.notes.count, 5)
        XCTAssertEqual(result.notes.first, "first")
        XCTAssertEqual(result.notes.last?.count, 200)
    }

    func testScoresUseCurrentStartsAndSkipUnfinishedOrMissedCycles() {
        let forecasts = [
            ForecastHistoryEntry(cycleStart: "2026-08-01", baselineStart: "2026-08-29", predictedStart: "2026-08-31"),
            ForecastHistoryEntry(cycleStart: "2026-08-30", baselineStart: "2026-09-27", predictedStart: "2026-09-28"),
            ForecastHistoryEntry(cycleStart: "2026-10-01", baselineStart: "2026-10-29", predictedStart: "2026-10-30")
        ]
        let scores = ForecastMath.score(forecasts, starts: [day("2026-10-01"), day("2026-08-30"), day("2026-08-01")])
        XCTAssertEqual(scores.count, 2)
        XCTAssertEqual(scores[0].actualStart, "2026-10-01")
        XCTAssertEqual(scores[0].aiError, 3)
        XCTAssertEqual(scores[0].mathError, 4)
        let edited = ForecastMath.score(forecasts, starts: [day("2026-10-01"), day("2026-08-29"), day("2026-08-01")])
        XCTAssertEqual(edited.count, 1)
        XCTAssertEqual(edited[0].aiError, -2)
        XCTAssertTrue(ForecastMath.score(forecasts, starts: [day("2026-10-01"), day("2026-08-01")]).isEmpty)
    }

    func testBenchesOnlyStrictlyWorseLastThreeAndRecomputes() {
        func score(_ start: String, _ ai: Int, _ math: Int) -> ForecastScore {
            ForecastScore(cycleStart: start, predictedStart: "", baselineStart: "", actualStart: "", aiError: ai, mathError: math)
        }
        let poor = [score("2026-09-01", -2, 1), score("2026-08-01", 2, -1), score("2026-07-01", 2, 1)]
        XCTAssertTrue(ForecastMath.isBenched(poor))
        XCTAssertFalse(ForecastMath.isBenched(Array(poor.prefix(2))))
        XCTAssertFalse(ForecastMath.isBenched([score("2026-09-01", -1, 1), score("2026-08-01", 1, -1), score("2026-07-01", 1, 1)]))
        XCTAssertFalse(ForecastMath.isBenched([score("2026-10-01", 0, 8)] + poor))
    }

    func testHashStableAcrossInputOrderAndChangesWithHistory() {
        let cycles = [(start: day("2026-09-01"), length: 30), (start: day("2026-08-01"), length: 31)]
        let hash = ForecastMath.inputsHash(lastStart: day("2026-10-01"), cycles: cycles, average: 30, spread: 2, completedLogCount: 4)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(hash, ForecastMath.inputsHash(lastStart: day("2026-10-01"), cycles: cycles.reversed(), average: 30, spread: 2, completedLogCount: 4))
        XCTAssertNotEqual(hash, ForecastMath.inputsHash(lastStart: day("2026-10-02"), cycles: cycles, average: 30, spread: 2, completedLogCount: 4))
        XCTAssertNotEqual(hash, ForecastMath.inputsHash(lastStart: day("2026-10-01"), cycles: cycles, average: 30, spread: 2, completedLogCount: 5))
    }

    func testSummaryExcludesPrivateNotesAndSortsTies() {
        let log = DayLog(date: day("2026-10-01"), flow: "Heavy", symptoms: ["Fatigue", "Cramps", "Cramps"], pain: 7, energy: 2, note: "PRIVATE diary text")
        let summary = ForecastMath.symptomSummary([log])
        XCTAssertFalse(summary.contains("PRIVATE"))
        XCTAssertTrue(summary.contains("Cramps: 1 days, Fatigue: 1 days"))
        XCTAssertTrue(summary.contains("max pain: 7"))
        XCTAssertTrue(summary.contains("heaviest flow: Heavy"))
    }

    func testBadJSONRejectsFractionalDaysAndMissingFields() {
        XCTAssertThrowsError(try JSONDecoder().decode(ForecastResponse.self, from: Data(#"{"shiftDays":1.5,"spreadDays":3,"reason":"Fine","notes":[]}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ForecastResponse.self, from: Data(#"{"shiftDays":0}"#.utf8)))
    }

    func testRequestReturnsValidResponse() async throws {
        let request = ForecastRequest()
        let value = try await request.run(timeoutNanoseconds: 1_000_000_000) { ForecastResponse(shiftDays: 0, spreadDays: 2, reason: "No change.", notes: []) }
        XCTAssertEqual(value.shiftDays, 0)
    }

    func testDeadlineDoesNotWaitForUncooperativeModel() async {
        let request = ForecastRequest(), start = Date()
        do {
            _ = try await request.run(timeoutNanoseconds: 20_000_000) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        continuation.resume(returning: ForecastResponse(shiftDays: 0, spreadDays: 2, reason: "Late", notes: []))
                    }
                }
            }
            XCTFail("Expected a timeout")
        } catch { XCTAssertLessThan(Date().timeIntervalSince(start), 0.4) }
    }

    func testCancellationReturnsPromptly() async {
        let request = ForecastRequest()
        let task = Task {
            try await request.run(timeoutNanoseconds: 5_000_000_000) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return ForecastResponse(shiftDays: 0, spreadDays: 2, reason: "Late", notes: [])
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
