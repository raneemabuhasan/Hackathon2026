import Foundation

struct PeriodPrediction: Codable {
    let windowStart: Date
    let windowEnd: Date
    let typicalLength: Int
    let completedLengths: [Int]
    // This is an empirical planning window, NOT a calibrated probability interval.
    let method = "recent-start-intervals-v1"
}

enum CyclePredictionEngine {
    /// At least two completed intervals (three starts). Uses the latest six.
    /// All observed intervals retained, including long gaps; missed logs cannot be inferred.
    static func predict(starts: [Date], asOf: Date, calendar: Calendar = .current) -> PeriodPrediction? {
        let today = calendar.startOfDay(for: asOf)
        let dates = Set(starts.map { calendar.startOfDay(for: $0) }).filter { $0 <= today }.sorted()
        guard dates.count >= 3, let last = dates.last else { return nil }
        let lengths = zip(dates, dates.dropFirst()).compactMap {
            calendar.dateComponents([.day], from: $0.0, to: $0.1).day
        }.suffix(6).filter { $0 > 0 }
        guard lengths.count >= 2 else { return nil }
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let typical = Int(mean.rounded())
        let deviation = sqrt(lengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(lengths.count))
        let margin = max(2, Int(ceil(deviation * 1.5)))
        let lower = max(1, min(lengths.min()!, typical - margin))
        let upper = max(lengths.max()!, typical + margin)
        return PeriodPrediction(windowStart: calendar.date(byAdding: .day, value: lower, to: last)!,
            windowEnd: calendar.date(byAdding: .day, value: upper, to: last)!,
            typicalLength: typical, completedLengths: Array(lengths))
    }
}
