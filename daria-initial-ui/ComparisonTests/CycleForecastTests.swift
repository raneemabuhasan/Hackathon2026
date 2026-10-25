import XCTest
@testable import PetalComparison

final class CycleForecastTests: XCTestCase {
    private func day(_ key: String) -> Date { LogDate.parse(key)! }
    private func response(shift: Int = 0, spread: Int = 3, category: String? = nil,
                          evidence: [String]? = nil) -> ForecastResponse {
        ForecastResponse(shiftDays: shift, spreadDays: spread,
            reasonCategory: category ?? (shift == 0 ? "no_clear_pattern" : "recent_history"),
            evidenceCycleStarts: evidence ?? (shift == 0 ? [] : ["2026-09-01", "2026-08-01"]))
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
        let evidence: Set<String> = ["2026-09-01", "2026-08-01"]
        let result = try XCTUnwrap(ForecastMath.clamp(response(shift: 3, spread: 6), baselineStart: day("2026-10-29"), baselineSpread: 3, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertEqual(LogDate.key(result.start), "2026-11-01")
        XCTAssertEqual(result.spread, 6)
        let narrow = try XCTUnwrap(ForecastMath.clamp(response(shift: -3, spread: 3), baselineStart: day("2026-10-29"), baselineSpread: 4, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertEqual(LogDate.key(narrow.start), "2026-10-26")
        XCTAssertEqual(narrow.spread, 3)
    }

    func testRejectsUnsafeCycleAndImpossibleWindow() {
        let evidence: Set<String> = ["2026-09-01", "2026-08-01"]
        XCTAssertNil(ForecastMath.clamp(response(shift: -3), baselineStart: day("2026-10-19"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertNil(ForecastMath.clamp(response(shift: 3), baselineStart: day("2026-11-15"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertNil(ForecastMath.clamp(response(), baselineStart: day("2026-10-29"), baselineSpread: 12, lastStart: day("2026-10-01"), allowedEvidence: []))
        XCTAssertNil(ForecastMath.clamp(response(category: "made_up"), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: []))
    }

    func testForecastExplanationIsAppOwnedAndEvidenceMustBeSupplied() throws {
        let evidence: Set<String> = ["2026-09-01", "2026-08-01"]
        let result = try XCTUnwrap(ForecastMath.clamp(response(shift: 1), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertEqual(result.reason, "Recent cycle records informed this estimate.")
        XCTAssertNil(ForecastMath.clamp(response(shift: 1, evidence: ["2030-01-01", "2030-02-01"]), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertNil(ForecastMath.clamp(response(shift: 1, evidence: ["2026-09-01"]), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: evidence))
        XCTAssertNil(ForecastMath.clamp(response(shift: 0, category: "no_clear_pattern", evidence: ["2026-09-01"]), baselineStart: day("2026-10-29"), baselineSpread: 2, lastStart: day("2026-10-01"), allowedEvidence: ["2026-09-01"]))
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
        let logs = [DayLog(date: day("2026-09-10"), flow: "Light", moods: ["Calm"], symptoms: ["Cramps"], pain: 2, energy: 3, note: "private")]
        let periods: [(start: Date, end: Date?)] = [(day("2026-08-01"), day("2026-08-05"))]
        func hash(cycles: [(start: Date, length: Int)] = cycles, logs: [DayLog] = logs, periods: [(start: Date, end: Date?)] = periods,
                  reference: Date = day("2026-10-21"), configuredCycleLength: Int = 28) -> String {
            ForecastMath.inputsHash(lastStart: day("2026-10-01"), cycles: cycles, periods: periods, logs: logs,
                average: 30, spread: 2, configuredCycleLength: configuredCycleLength, configuredPeriodLength: 5,
                referenceDate: reference)
        }
        let value = hash()
        XCTAssertEqual(value.count, 64)
        XCTAssertEqual(value, hash(cycles: cycles.reversed().map { $0 }))
        XCTAssertEqual(value, hash(logs: logs.reversed().map { $0 }))
        var edited = logs[0]; edited.pain = 8
        XCTAssertNotEqual(value, hash(logs: [edited]))
        edited = logs[0]; edited.symptoms = ["Fatigue"]
        XCTAssertNotEqual(value, hash(logs: [edited]))
        edited = logs[0]; edited.moods = ["Irritable"]
        XCTAssertNotEqual(value, hash(logs: [edited]))
        XCTAssertNotEqual(value, hash(logs: []))
        XCTAssertNotEqual(value, hash(logs: logs + [DayLog(date: day("2026-09-11"), symptoms: ["Fatigue"])]))
        edited = logs[0]; edited.note = "different private note"
        XCTAssertEqual(value, hash(logs: [edited]))
        XCTAssertNotEqual(value, hash(reference: day("2026-10-22")))
        XCTAssertNotEqual(value, hash(configuredCycleLength: 32))
        XCTAssertNotEqual(value, hash(periods: [(day("2026-08-01"), day("2026-08-06"))]))
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
        XCTAssertThrowsError(try JSONDecoder().decode(ForecastResponse.self, from: Data(#"{"shiftDays":1.5,"spreadDays":3,"reasonCategory":"recent_history","evidenceCycleStarts":[]}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(ForecastResponse.self, from: Data(#"{"shiftDays":0}"#.utf8)))
    }

    func testRequestReturnsValidResponse() async throws {
        let request = ForecastRequest()
        let value = try await request.run(timeoutNanoseconds: 1_000_000_000) { ForecastResponse(shiftDays: 0, spreadDays: 2, reasonCategory: "no_clear_pattern", evidenceCycleStarts: []) }
        XCTAssertEqual(value.shiftDays, 0)
    }

    func testDeadlineDoesNotWaitForUncooperativeModel() async {
        let request = ForecastRequest(), start = Date()
        do {
            _ = try await request.run(timeoutNanoseconds: 20_000_000) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        continuation.resume(returning: ForecastResponse(shiftDays: 0, spreadDays: 2, reasonCategory: "no_clear_pattern", evidenceCycleStarts: []))
                    }
                }
            }
            XCTFail("Expected a timeout")
        } catch { XCTAssertLessThan(Date().timeIntervalSince(start), 0.4) }
    }

    func testRetryBackoffIsBoundedAndStopsAfterThreeAttempts() {
        XCTAssertNil(ForecastRetryPolicy.delay(afterFailureCount: 0))
        XCTAssertEqual(ForecastRetryPolicy.delay(afterFailureCount: 1), 2)
        XCTAssertEqual(ForecastRetryPolicy.delay(afterFailureCount: 2), 4)
        XCTAssertNil(ForecastRetryPolicy.delay(afterFailureCount: 3))
    }

    func testCancellationReturnsPromptly() async {
        let request = ForecastRequest()
        let task = Task {
            try await request.run(timeoutNanoseconds: 5_000_000_000) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return ForecastResponse(shiftDays: 0, spreadDays: 2, reasonCategory: "no_clear_pattern", evidenceCycleStarts: [])
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
