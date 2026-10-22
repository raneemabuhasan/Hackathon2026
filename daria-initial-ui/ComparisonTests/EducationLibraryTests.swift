import XCTest
@testable import PetalComparison

final class EducationLibraryTests: XCTestCase {
    func library() throws -> EducationLibrary { try EducationLibrary.bundled() }

    func testBundledSourcesAndPassagesHaveTrustedMetadata() throws {
        let library = try library()
        XCTAssertEqual(library.sources.count, 6)
        XCTAssertEqual(library.passages.count, 11)
        XCTAssertEqual(Set(library.sources.map { $0.url.absoluteString }), EducationLibrary.allowedURLs)
        XCTAssertTrue(library.passages.allSatisfy { !$0.topics.isEmpty && !$0.keywords.isEmpty && !$0.limitations.isEmpty })
        let counting = try XCTUnwrap(library.passages.first { $0.id == "cycle-counting" })
        XCTAssertEqual(counting.sourceID, "cc-menstrual-cycle")
        let phases = try XCTUnwrap(library.passages.first { $0.id == "cycle-phases" })
        XCTAssertEqual(phases.sourceID, "cc-menstrual-cycle")
        XCTAssertTrue(phases.text.contains("also starts then"))
    }

    func testSearchUsesKeywordsTopicsAndStableRanking() throws {
        let library = try library()
        XCTAssertEqual(library.search(query: "How do I count cycle length?").first?.id, "cycle-counting")
        XCTAssertEqual(library.search(query: "FOLLICULAR phase overlap").first?.id, "cycle-phases")
        XCTAssertTrue(library.search(query: "", topics: ["ovulation"]).contains { $0.id == "cycle-ovulation-luteal" })
        XCTAssertTrue(library.search(query: "cycle syncing clinical evidence").contains { $0.id == "syncing-evidence" })
        XCTAssertTrue(library.search(query: "iron foods during menstruation", topics: ["nutrition"]).contains { $0.id == "nutrition-menstrual" })
        XCTAssertLessThanOrEqual(library.search(query: "phase foods", topics: ["nutrition", "phases"], limit: 100).count, 6)
    }

    func testUnsupportedQuestionsDoNotGetGenericPeriodMatches() throws {
        let library = try library()
        for question in ["What ibuprofen dose treats menstrual cramps?", "Does cycle syncing cure PCOS?",
                         "Which supplement treats endometriosis?", "How do black holes form?", ""] {
            XCTAssertTrue(library.search(query: question).isEmpty, question)
        }
    }

    func testCitationsResolveOnlyRetrievedPassagesAndDeduplicate() throws {
        let library = try library()
        var evidence = EducationEvidence()
        evidence.record(library.search(query: "count cycle length"))
        let answer = try evidence.validate("Count successive starts [edu:cycle-counting]. Bleeding duration differs [edu:cycle-counting].",
                                           library: library, required: true)
        XCTAssertEqual(answer.text, "Count successive starts [1]. Bleeding duration differs [1].")
        XCTAssertEqual(answer.citations.count, 1)
        XCTAssertEqual(answer.citations.first?.url.absoluteString,
                       "https://my.clevelandclinic.org/health/articles/10132-menstrual-cycle")
        XCTAssertEqual(answer.citations.first?.sourceID, "cc-menstrual-cycle")
    }

    func testRejectsForgedStaleMissingAndUnretrievedCitations() throws {
        let library = try library()
        var evidence = EducationEvidence()
        evidence.record(library.search(query: "count cycle length"))
        for reply in ["Claim [edu:invented]", "Claim [edu:cc-menstrual-cycle]", "Claim [edu:nutrition-menstrual]", "Claim without a citation",
                      "Claim [edu:cycle-counting] https://evil.example", "Claim [edu:cycle-counting] [1]",
                      "Claim [edu:cycle-counting] [source](javascript:alert(1))",
                      "Claim [edu:cycle-counting] [edu:broken"] {
            XCTAssertThrowsError(try evidence.validate(reply, library: library, required: true), reply)
        }
        let nextTurn = EducationEvidence()
        XCTAssertThrowsError(try nextTurn.validate("Claim [edu:cycle-counting]", library: library, required: false))
        XCTAssertThrowsError(try nextTurn.validate("Unretrieved explanation", library: library, required: true))
    }

    func testOnlyCitedPassagesBecomeLinksInFirstUseOrder() throws {
        let library = try library()
        var evidence = EducationEvidence()
        evidence.record(library.passages)
        let result = try evidence.validate("Optional ideas [edu:nutrition-menstrual]. Count starts [edu:cycle-counting]. More ideas [edu:nutrition-menstrual].",
                                           library: library, required: true)
        XCTAssertEqual(result.citations.map(\.number), [1, 2])
        XCTAssertEqual(result.citations.map(\.passageID), ["nutrition-menstrual", "cycle-counting"])
        XCTAssertEqual(result.citations.map(\.sourceID), ["cc-cycle-syncing", "cc-menstrual-cycle"])
        XCTAssertTrue(result.text.hasSuffix("More ideas [1]."))
    }

    func testEmptySearchAndInsufficientEvidenceFailClosed() throws {
        let library = try library()
        var empty = EducationEvidence()
        empty.record([])
        let answer = try empty.validate("Invented treatment [edu:cycle-counting]", library: library, required: true)
        XCTAssertEqual(answer.text, EducationEvidence.unsupported)
        XCTAssertTrue(answer.citations.isEmpty)
        var partial = EducationEvidence()
        partial.record(library.search(query: "cycle phases"))
        XCTAssertEqual(try partial.validate("[education:unsupported]", library: library, required: true).text,
                       EducationEvidence.unsupported)
    }

    func testInternalRetrievalLanguageIsNeverDisplayed() throws {
        let library = try library()
        var evidence = EducationEvidence()
        evidence.record(library.get(.fatigue))
        for text in ["I don't have a passage in the bundled education library.", "get_education failed", "I have no supporting passage."] {
            let answer = try evidence.validate(text, library: library, required: true)
            XCTAssertEqual(answer.text, EducationEvidence.unsupported)
            XCTAssertTrue(answer.citations.isEmpty)
        }
    }

    func testUnrelatedToolRepliesRemainUnchanged() throws {
        let evidence = EducationEvidence()
        for reply in ["Saved your cramps for March 2, 2026.", "Your reminder is set.",
                      "Here are your recorded cycles:", "Your estimated next period is between March 2 and March 6, 2026."] {
            let result = try evidence.validate(reply, library: library(), required: false)
            XCTAssertEqual(result.text, reply)
            XCTAssertTrue(result.citations.isEmpty)
        }
        for prompt in ["Log cramps today", "Remind me to restock pads", "Show all my recorded cycles", "When is my next period?",
                       "Can you compare my last three cycles?", "Can you log cramps today?"] {
            XCTAssertFalse(EducationLibrary.requiresEducation(prompt), prompt)
        }
        for prompt in ["What is the follicular phase?", "How do I count cycle length?", "Does cycle syncing cure PCOS?", "What should I eat?"] {
            XCTAssertTrue(EducationLibrary.requiresEducation(prompt), prompt)
        }
    }

    func testTamperedLibraryCannotSupplyCitationURLs() throws {
        let original = try JSONEncoder().encode(library())
        let text = try XCTUnwrap(String(data: original, encoding: .utf8))
        let altered = text.replacingOccurrences(of: "health.clevelandclinic.org", with: "evil.example")
        XCTAssertThrowsError(try EducationLibrary.decode(Data(altered.utf8)))
    }
}
