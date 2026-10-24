import Foundation
import CryptoKit

struct ForecastResponse: Codable, Sendable {
    let shiftDays: Int
    let spreadDays: Int
    let reason: String
    let notes: [String]
}

/// Date-only facts; no Firebase dependency, so validation and accuracy can be tested locally.
struct ForecastHistoryEntry: Equatable {
    let cycleStart: String
    let baselineStart: String
    let predictedStart: String
}

struct ForecastScore: Equatable {
    let cycleStart: String
    let predictedStart: String
    let baselineStart: String
    let actualStart: String
    let aiError: Int
    let mathError: Int
}

struct ForecastEligibility {
    var consent: Bool
    var predictionsEnabled: Bool
    var naturalCycle: Bool
    var completedCycles: Int
    var dataReady: Bool
    var predictionsReady: Bool
    var deletingData: Bool
    var stopped: Bool
    var benched: Bool

    var allowed: Bool {
        consent && predictionsEnabled && naturalCycle && completedCycles >= 3 && dataReady
            && predictionsReady && !deletingData && !stopped && !benched
    }
}

enum ForecastMath {
    static func days(_ a: Date, from b: Date) -> Int {
        LogDate.calendar.dateComponents([.day], from: b, to: a).day ?? 0
    }

    static func clamp(_ response: ForecastResponse, baselineStart: Date, baselineSpread: Int,
                      lastStart: Date) -> (start: Date, spread: Int, reason: String, notes: [String])? {
        let lower = max(2, baselineSpread - 1), upper = min(10, baselineSpread + 3)
        guard lower <= upper,
              let start = LogDate.calendar.date(byAdding: .day, value: min(3, max(-3, response.shiftDays)), to: baselineStart),
              (18...45).contains(days(start, from: lastStart)) else { return nil }
        let reason = String(response.reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !reason.isEmpty else { return nil }
        let notes = response.notes.lazy.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)) }
            .filter { !$0.isEmpty }.prefix(5)
        return (start, min(upper, max(lower, response.spreadDays)), reason, Array(notes))
    }

    static func score(_ forecasts: [ForecastHistoryEntry], starts: [Date]) -> [ForecastScore] {
        let ordered = Array(Set(starts.map { LogDate.calendar.startOfDay(for: $0) })).sorted()
        let byStart = Dictionary(grouping: forecasts, by: \.cycleStart)
        return zip(ordered, ordered.dropFirst()).compactMap { start, actual in
            let key = LogDate.key(start)
            guard (18...45).contains(days(actual, from: start)), let forecast = byStart[key]?.first,
                  let predicted = LogDate.parse(forecast.predictedStart),
                  let baseline = LogDate.parse(forecast.baselineStart),
                  (18...45).contains(days(predicted, from: start)),
                  abs(days(predicted, from: baseline)) <= 3 else { return nil }
            return ForecastScore(cycleStart: key, predictedStart: forecast.predictedStart,
                                 baselineStart: forecast.baselineStart, actualStart: LogDate.key(actual),
                                 aiError: days(actual, from: predicted), mathError: days(actual, from: baseline))
        }.reversed()
    }

    static func isBenched(_ scores: [ForecastScore]) -> Bool {
        let recent = scores.sorted { $0.cycleStart > $1.cycleStart }.prefix(3)
        return recent.count == 3 && recent.reduce(0) { $0 + abs($1.aiError) } > recent.reduce(0) { $0 + abs($1.mathError) }
    }

    static func inputsHash(lastStart: Date, cycles: [(start: Date, length: Int)], average: Int,
                           spread: Int, completedLogCount: Int) -> String {
        let cycles = cycles.sorted { $0.start < $1.start }.map { "\(LogDate.key($0.start)):\($0.length)" }
        let text = ([LogDate.key(lastStart)] + cycles + [String(average), String(spread), String(completedLogCount)]).joined(separator: "|")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func symptomSummary(_ logs: [DayLog]) -> String {
        let ordered = logs.sorted { $0.date < $1.date }
        guard !ordered.isEmpty else { return "No saved daily logs." }
        var counts: [String: Int] = [:]
        for log in ordered { for symptom in Set(log.symptoms) { counts[symptom, default: 0] += 1 } }
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3).map { "\($0.key): \($0.value) days" }.joined(separator: ", ")
        let energy = Double(ordered.reduce(0) { $0 + min(5, max(1, $1.energy)) }) / Double(ordered.count)
        let flow = ["None", "Light", "Medium", "Heavy"]
        let heaviest = ordered.map { flow.firstIndex(of: $0.flow) ?? 0 }.max() ?? 0
        return "Logged days: \(ordered.count); top symptoms: \(top.isEmpty ? "none" : top); max pain: \(min(10, max(0, ordered.map(\.pain).max() ?? 0))); average energy: \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), energy)); heaviest flow: \(flow[heaviest])."
    }
}

/// Resolves on the deadline even if a model request ignores task cancellation.
actor ForecastRequest {
    enum Failure: Error { case timedOut }
    private var continuation: CheckedContinuation<ForecastResponse, Error>?
    private var result: Result<ForecastResponse, Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    func run(timeoutNanoseconds: UInt64 = 15_000_000_000, operation: @escaping @Sendable () async throws -> ForecastResponse) async throws -> ForecastResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let result { continuation.resume(with: result); return }
                self.continuation = continuation
                work = Task {
                    do { self.finish(.success(try await operation())) }
                    catch { self.finish(.failure(error)) }
                }
                timer = Task {
                    do { try await Task.sleep(nanoseconds: timeoutNanoseconds); self.finish(.failure(Failure.timedOut)) }
                    catch { /* The successful request cancelled the timer. */ }
                }
            }
        } onCancel: {
            Task { await self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<ForecastResponse, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
        work?.cancel(); timer?.cancel()
        work = nil; timer = nil
    }
}
