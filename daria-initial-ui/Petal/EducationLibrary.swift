import Foundation

struct EducationSource: Codable {
    let id: String
    let title: String
    let url: URL
    let limitations: String
}

struct EducationPassage: Codable, Identifiable {
    let id: String
    let sourceID: String
    let title: String
    let topics: [String]
    let keywords: [String]
    let text: String
    let limitations: String
    var suggestedPrompts: [String]? = nil
}

struct EducationCitation: Identifiable, Equatable {
    var id: String { passageID }
    let number: Int
    let passageID: String
    let sourceID: String
    let sourceTitle: String
    let passageTitle: String
    let url: URL
}

struct EducationLibrary: Codable {
    let version: Int
    let reviewedOn: String
    let sources: [EducationSource]
    let passages: [EducationPassage]

    static let allowedURLs: Set<String> = [
        "https://health.clevelandclinic.org/cycle-syncing",
        "https://www.nhs.uk/symptoms/period-pain/",
        "https://www.nhs.uk/conditions/pre-menstrual-syndrome/",
        "https://www.nhs.uk/conditions/heavy-periods/",
        "https://www.nhs.uk/symptoms/tiredness-and-fatigue/",
        "https://my.clevelandclinic.org/health/articles/10132-menstrual-cycle"
    ]

    static func bundled() throws -> EducationLibrary {
        #if PETAL_EDUCATION_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "education", withExtension: "json") else {
            throw LibraryError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> EducationLibrary {
        let library = try JSONDecoder().decode(Self.self, from: data)
        guard library.version == 1,
              Set(library.sources.map(\.id)).count == library.sources.count,
              Set(library.passages.map(\.id)).count == library.passages.count,
              !library.sources.isEmpty, !library.passages.isEmpty,
              library.sources.allSatisfy({ allowedURLs.contains($0.url.absoluteString) }),
              library.passages.allSatisfy({ passage in
                  library.sources.contains { $0.id == passage.sourceID }
                    && !passage.text.isEmpty && !passage.limitations.isEmpty
              }) else { throw LibraryError.invalidLibrary }
        return library
    }

    enum LibraryError: Error { case missingResource, invalidLibrary }

    func get(_ topic: EducationTopic) -> [EducationPassage] {
        let ids: Set<String>
        switch topic {
        case .definitions: ids = ["cycle-definition", "cycle-counting"]
        case .phases: ids = ["cycle-phases", "cycle-ovulation-luteal"]
        case .counting: ids = ["cycle-counting"]
        case .cramps: ids = ["nhs-cramps"]
        case .pms: ids = ["nhs-pms"]
        case .heavyPeriods: ids = ["nhs-heavy-periods"]
        case .fatigue: ids = ["nhs-fatigue", "nhs-pms"]
        case .nutrition: ids = ["syncing-evidence", "nutrition-menstrual", "nutrition-other-phases"]
        case .cycleSyncing: ids = ["syncing-evidence"]
        case .unsupported: ids = []
        }
        return passages.filter { ids.contains($0.id) }
    }

    func suggestedPrompts(for citations: [EducationCitation]) -> [String] {
        var seen: Set<String> = []
        return Array(citations.flatMap { citation in
            passages.first { $0.id == citation.passageID }?.suggestedPrompts ?? []
        }.filter { !$0.isEmpty && $0.count <= 100 && seen.insert($0).inserted }.prefix(3))
    }

    /// Deliberately small lexical search, not web search or a medical knowledge base.
    func search(query: String, topics: [String] = [], limit: Int = 4) -> [EducationPassage] {
        let words = Self.tokens(query)
        let topicWords = Set(topics.flatMap { Self.tokens($0) })
        guard !words.isEmpty || !topicWords.isEmpty else { return [] }
        // These subjects are outside this curated library even if the question also says "period".
        let unsupported: Set<String> = ["dosage", "dose", "medication", "ibuprofen", "supplement", "supplements",
            "endometriosis", "pcos", "pmos", "cancer", "thyroid", "diagnose", "diagnosis", "infertility"]
        guard words.isDisjoint(with: unsupported) else { return [] }
        let ranked = passages.compactMap { passage -> (EducationPassage, Int)? in
            let keys = Set(passage.keywords.flatMap { Self.tokens($0) })
            let tags = Set(passage.topics.flatMap { Self.tokens($0) })
            let queryHits = words.intersection(keys.union(tags)).count
            let topicHits = topicWords.intersection(tags).count
            guard queryHits > 0 || topicHits > 0 else { return nil }
            return (passage, queryHits * 2 + topicHits * 3)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        return Array(ranked.prefix(min(max(limit, 1), 6)).map(\.0))
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    /// Covers explicit educational prompts as an extra guard if the model forgets retrieval.
    /// The model instruction also covers conversational follow-ups, which lexical routing cannot fully identify.
    static func requiresEducation(_ text: String) -> Bool {
        if CompanionResponseFocus(message: text).wantsMealIdeas { return true }
        let q = text.lowercased()
        let words = tokens(text)
        let educational = ["what is", "what are", "what dose", "which", "can", "does", "how", "why", "explain", "define", "teach", "tell me about"]
            .contains { q.contains($0) }
        let topics: Set<String> = ["menstruation", "menstrual", "cycle", "cycles", "period", "phases", "phase",
            "follicular", "luteal", "ovulation", "hormones", "nutrition", "cramps", "pcos", "endometriosis",
            "normal", "pms", "heavy", "pain", "tired", "fatigue", "grumpy", "irritable", "mood", "symptoms", "exhausted", "anxious", "sad", "feeling"]
        let personalOnly = ["my next period", "my cycle length", "my current phase", "my saved", "my recorded",
                            "my last", "my previous", "my cycles", "phase am i", "compare", "remind", "log "]
            .contains { q.contains($0) }
        let explanation = ["why", "explain", "what causes", "what could cause"].contains { q.contains($0) }
        return (educational && (!personalOnly || explanation) && !words.isDisjoint(with: topics))
            || q.contains("cycle syncing") || q.contains("cycle-syncing")
            || q.contains("is this normal") || q.contains("when should i seek help")
            || q.contains("what should i eat") || q.contains("foods for")
    }
}

struct EducationAnswer {
    let text: String
    let citations: [EducationCitation]
}

/// A fresh instance is used for each reply; prior-turn evidence never authorizes a citation.
struct EducationEvidence {
    private(set) var searched = false
    private(set) var retrievedIDs: Set<String> = []
    static let unsupported = "I can’t give a reliable explanation for that specific question. Could you tell me a little more about what you’re experiencing? A clinician can help with symptoms that persist or worry you."

    mutating func record(_ passages: [EducationPassage]) {
        searched = true
        retrievedIDs.formUnion(passages.map(\.id))
    }

    enum ValidationError: Error { case missingRetrieval, invalidCitation, missingCitation, untrustedLink }

    func validate(_ raw: String, library: EducationLibrary?, required: Bool) throws -> EducationAnswer {
        if required && !searched { throw ValidationError.missingRetrieval }
        let revealsInternals = raw.range(of: #"(?i)bundled (?:education )?library|knowledge library|(?:no|have a|have any|have the) (?:supporting )?passage|search_education|get_education"#, options: .regularExpression) != nil
        if revealsInternals || (searched && (retrievedIDs.isEmpty || raw.contains("[education:unsupported]"))) {
            return EducationAnswer(text: Self.unsupported, citations: [])
        }
        let marker = try NSRegularExpression(pattern: #"\[edu:([^\]]+)\]"#)
        let range = NSRange(raw.startIndex..., in: raw)
        let matches = marker.matches(in: raw, range: range)
        if searched && matches.isEmpty { throw ValidationError.missingCitation }
        if !searched && !matches.isEmpty { throw ValidationError.invalidCitation }
        // All clickable links are resolved below, never copied from model text.
        if searched || required || !matches.isEmpty {
            let links = try NSRegularExpression(pattern: #"(?i)(?:https?|ftp|javascript|data):|www\.|\]\s*\(|\[\d+\]"#)
            guard links.firstMatch(in: raw, range: range) == nil else { throw ValidationError.untrustedLink }
        }
        var citations: [EducationCitation] = []
        var replacements: [(NSRange, String)] = []
        for match in matches {
            let id = (raw as NSString).substring(with: match.range(at: 1))
            guard retrievedIDs.contains(id), let library,
                  let passage = library.passages.first(where: { $0.id == id }),
                  let source = library.sources.first(where: { $0.id == passage.sourceID }),
                  EducationLibrary.allowedURLs.contains(source.url.absoluteString) else {
                throw ValidationError.invalidCitation
            }
            let number: Int
            if let previous = citations.first(where: { $0.passageID == id }) { number = previous.number }
            else {
                number = citations.count + 1
                citations.append(EducationCitation(number: number, passageID: id, sourceID: source.id,
                    sourceTitle: source.title, passageTitle: passage.title, url: source.url))
            }
            replacements.append((match.range, "[\(number)]"))
        }
        let output = NSMutableString(string: raw)
        for (range, text) in replacements.reversed() { output.replaceCharacters(in: range, with: text) }
        // Malformed markers must not sneak through as apparently valid references.
        guard !output.lowercased.contains("[edu") else { throw ValidationError.invalidCitation }
        return EducationAnswer(text: output as String, citations: citations)
    }
}


enum EducationTopic: String, CaseIterable {
    case definitions, phases, counting, cramps, pms, fatigue, nutrition
    case heavyPeriods = "heavy_periods"
    case cycleSyncing = "cycle_syncing"
    case unsupported
}
