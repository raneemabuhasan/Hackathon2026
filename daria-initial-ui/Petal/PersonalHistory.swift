import Foundation

struct PersonalHistory: Codable {
    var version = 1
    var starts: [Date] = []
    var logs: [DayLog] = []
    var periodEnds: [Date: Date] = [:]
    var diets: Set<String> = []
    var avoid: Set<String> = []

    mutating func save(_ entry: DayLog, calendar: Calendar = .current) {
        // One daily log. Preserve its identity when replacing the same day.
        var replacement = entry
        if let existing = logs.first(where: { calendar.isDate($0.date, inSameDayAs: entry.date) }) {
            replacement.id = existing.id
        }
        logs.removeAll { $0.id == entry.id || calendar.isDate($0.date, inSameDayAs: entry.date) }
        logs.append(replacement)
    }
}

/// Shared local history storage, injectable for testing and future sync integration.
protocol HistoryRepository {
    func load() throws -> PersonalHistory
    func save(_ history: PersonalHistory) throws
}

// TODO(storage teammate): implement HistoryRepository for Firebase and inject it into CycleStore.
struct PersonalHistoryRepository: HistoryRepository {
    let url: URL

    static func deviceRepository() throws -> PersonalHistoryRepository {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Petal", isDirectory: true)
        return PersonalHistoryRepository(url: directory.appendingPathComponent("personal-history-v1.json"))
    }

    func load() throws -> PersonalHistory {
        guard FileManager.default.fileExists(atPath: url.path) else { return PersonalHistory() }
        let history = try JSONDecoder().decode(PersonalHistory.self, from: Data(contentsOf: url))
        guard history.version == 1 else {
            throw NSError(domain: "PetalHistory", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported history format. Existing file was preserved."])
        }
        return history
    }

    func save(_ history: PersonalHistory) throws {
        let data = try JSONEncoder().encode(history)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
