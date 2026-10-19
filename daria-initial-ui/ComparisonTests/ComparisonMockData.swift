import Foundation
@testable import PetalComparison

/// Fictional fixture, also used by unit tests. Dates supplied by the caller.
enum ComparisonMockData {
    static func logs(starts: [Date], calendar: Calendar = .current) -> [ComparisonEntry] {
        starts.sorted().suffix(3).enumerated().flatMap { index, start in
            [ComparisonEntry(date: start, symptoms: ["Cramps", "Fatigue"], pain: 3 + index * 2),
             ComparisonEntry(date: calendar.date(byAdding: .day, value: 1, to: start)!,
                    symptoms: ["Cramps"], pain: nil),
             ComparisonEntry(date: calendar.date(byAdding: .day, value: 2, to: start)!,
                    symptoms: index == 2 ? ["Fatigue", "Headache"] : ["Fatigue"])]
        }
    }
}
