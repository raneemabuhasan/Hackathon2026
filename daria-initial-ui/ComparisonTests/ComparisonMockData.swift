import Foundation
@testable import PetalComparison

/// Fictional fixture, also used by unit tests. Dates supplied by the caller.
enum ComparisonMockData {
    static func logs(starts: [Date], calendar: Calendar = .current) -> [DayLog] {
        starts.sorted().suffix(3).enumerated().flatMap { index, start in
            [DayLog(date: start, flow: "Heavy", symptoms: ["Cramps", "Fatigue"], pain: 3 + index * 2),
             DayLog(date: calendar.date(byAdding: .day, value: 1, to: start)!,
                    flow: "Medium", symptoms: ["Cramps"], pain: nil),
             DayLog(date: calendar.date(byAdding: .day, value: 2, to: start)!,
                    flow: "Light", symptoms: index == 2 ? ["Fatigue", "Headache"] : ["Fatigue"])]
        }
    }
}
