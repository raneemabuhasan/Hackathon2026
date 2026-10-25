import Foundation
import CryptoKit

struct ForecastResponse: Codable, Sendable {
    let shiftDays: Int
    let spreadDays: Int
    let reasonCategory: String
    let evidenceCycleStarts: [String]
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

struct ForecastScoreInput {
    let cycleStart: String
    let predictedStart: String
    let baselineStart: String
    let actualStart: String
    let aiError: Int
    let mathError: Int
}

enum ForecastRetryPolicy {
    static let maximumAttempts = 3

    /// Retry transient failures with a short capped backoff; invalid model output is not retried.
    static func delay(afterFailureCount count: Int) -> TimeInterval? {
        guard count > 0, count < maximumAttempts else { return nil }
        return min(30, pow(2, Double(count)))
    }
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
                      lastStart: Date, allowedEvidence: Set<String>) -> (start: Date, spread: Int, reason: String)? {
        let lower = max(2, baselineSpread - 1), upper = min(10, baselineSpread + 3)
        guard lower <= upper,
              response.evidenceCycleStarts.count <= 6,
              Set(response.evidenceCycleStarts).count == response.evidenceCycleStarts.count,
              Set(response.evidenceCycleStarts).isSubset(of: allowedEvidence),
              (-3...3).contains(response.shiftDays), (lower...upper).contains(response.spreadDays),
              response.reasonCategory == "recent_history" || response.reasonCategory == "no_clear_pattern",
              response.reasonCategory != "no_clear_pattern" || response.shiftDays == 0,
              response.reasonCategory != "no_clear_pattern" || (response.evidenceCycleStarts.isEmpty && response.spreadDays == baselineSpread),
              response.reasonCategory != "recent_history" || !response.evidenceCycleStarts.isEmpty,
              response.shiftDays == 0 || response.evidenceCycleStarts.count >= 2 else { return nil }
        guard let start = LogDate.calendar.date(byAdding: .day, value: response.shiftDays, to: baselineStart),
              (18...45).contains(days(start, from: lastStart)) else { return nil }
        let reason = response.reasonCategory == "no_clear_pattern"
            ? "There isn’t a clear pattern, so this stays close to your average."
            : "Recent cycle records informed this estimate."
        return (start, response.spreadDays, reason)
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

    static func inputsHash(lastStart: Date, cycles: [(start: Date, length: Int)],
                           periods: [(start: Date, end: Date?)], logs: [DayLog], average: Int,
                           spread: Int, configuredCycleLength: Int, configuredPeriodLength: Int,
                           referenceDate: Date, scores: [ForecastScoreInput] = [],
                           logicVersion: String = "forecast-v2") -> String {
        let cycleParts = cycles.sorted { $0.start < $1.start }.map { "cycle:\(LogDate.key($0.start)):\($0.length)" }
        let periodParts = periods.map { "period:\(LogDate.key($0.start)):\($0.end.map { LogDate.key($0) } ?? "open")" }.sorted()
        let logParts = logs.map { log in
            let symptoms = Set(log.symptoms).sorted().joined(separator: ",")
            let moods = Set(log.moods).sorted().joined(separator: ",")
            return "log:\(LogDate.key(log.date)):\(log.flow):\(symptoms):\(moods):\(log.pain):\(log.energy)"
        }.sorted()
        let scoreParts = scores.map {
            "score:\($0.cycleStart):\($0.predictedStart):\($0.baselineStart):\($0.actualStart):\($0.aiError):\($0.mathError)"
        }.sorted()
        let text = ([logicVersion, "last:\(LogDate.key(lastStart))"] + cycleParts + periodParts + logParts
            + scoreParts
            + ["average:\(average)", "spread:\(spread)", "configured-cycle:\(configuredCycleLength)",
               "configured-period:\(configuredPeriodLength)", "today:\(LogDate.key(referenceDate))"]).joined(separator: "|")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func symptomSummary(_ logs: [DayLog]) -> String {
        let ordered = logs.sorted { $0.date < $1.date }
        guard !ordered.isEmpty else { return "No saved daily logs." }
        var counts: [String: Int] = [:]
        var moodCounts: [String: Int] = [:]
        for log in ordered {
            for symptom in Set(log.symptoms) { counts[symptom, default: 0] += 1 }
            for mood in Set(log.moods) { moodCounts[mood, default: 0] += 1 }
        }
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3).map { "\($0.key): \($0.value) days" }.joined(separator: ", ")
        let topMoods = moodCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3).map { "\($0.key): \($0.value) days" }.joined(separator: ", ")
        let energy = Double(ordered.reduce(0) { $0 + min(5, max(1, $1.energy)) }) / Double(ordered.count)
        let flow = ["None", "Light", "Medium", "Heavy"]
        let heaviest = ordered.map { flow.firstIndex(of: $0.flow) ?? 0 }.max() ?? 0
        return "Logged days: \(ordered.count); top symptoms: \(top.isEmpty ? "none" : top); top moods: \(topMoods.isEmpty ? "none" : topMoods); max pain: \(min(10, max(0, ordered.map(\.pain).max() ?? 0))); average energy: \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), energy)); heaviest flow: \(flow[heaviest])."
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
