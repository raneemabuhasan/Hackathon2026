import XCTest
@testable import PetalComparison

final class CompanionLoggingTests: XCTestCase {
    let date = LogDate.parse("2026-10-20")!

    func testCompanionUpdatesPreserveSpottingAndCustomFlow() throws {
        for flow in ["Spotting", "Very light"] {
            var existing = DayLog(date: date)
            existing.flow = flow
            existing.note = "Keep this note"
            let updated = try CompanionLogPatch(date: date, symptoms: ["Cramps"])
                .merged(with: existing, today: date)
            XCTAssertEqual(updated.flow, flow)
            XCTAssertEqual(updated.note, existing.note)
            XCTAssertEqual(updated.symptoms, ["Cramps"])
        }
    }

    func testExplicitCompanionFlowRemainsValidated() throws {
        XCTAssertThrowsError(try CompanionLogPatch(date: date, flow: "Unknown flow")
            .merged(with: nil, today: date))
        XCTAssertEqual(try CompanionLogPatch(date: date, flow: "Spotting")
            .merged(with: nil, today: date).flow, "Spotting")
    }

    func testFeelingThenConfirmationRetainsContextAcrossChatRecreationAndMidnight() {
        var state = LoggingConversation()
        XCTAssertEqual(state.receive("I'm feeling really tired today", now: date), .offer)
        let original = state.pending!
        let nextDay = LogDate.calendar.date(byAdding: .day, value: 1, to: date)!
        // The state lives outside Assistant; a new model chat doesn't alter it.
        XCTAssertEqual(state.receive("Yes, log it", now: nextDay), .authorized(original))
        XCTAssertEqual(original.resolvedDate, date)
        XCTAssertEqual(original.text, "I'm feeling really tired today")
        XCTAssertNil(original.painRating)
        XCTAssertNil(original.flow)
        state.saved()
        XCTAssertEqual(state.receive("Yes, log it", now: nextDay), .unrelated)
    }

    func testExplicitCommandsAndUnrelatedTools() {
        for text in ["Log cramps today", "Please save fatigue yesterday", "Can you record a headache today?", "Add tired to today's log",
                     "I'm really tired, can you log that?", "I'm feeling tired, please log it"] {
            var state = LoggingConversation()
            guard case .authorized(let authorization) = state.receive(text, now: date) else {
                return XCTFail("Not authorized: \(text)")
            }
            XCTAssertEqual(authorization.text, text)
        }
        for text in ["Show my recorded cycles", "What is the follicular phase?", "Remind me to restock pads", "What should I eat?", "Show my saved logs"] {
            var state = LoggingConversation()
            XCTAssertEqual(state.receive(text, now: date), .unrelated, text)
        }
    }

    func testDecliningAndUnrelatedTopicClearConsent() {
        var state = LoggingConversation()
        _ = state.receive("I have a headache", now: date)
        XCTAssertEqual(state.receive("No, don't save it", now: date), .declined)
        XCTAssertEqual(state.receive("yes", now: date), .unrelated)
        _ = state.receive("I feel tired", now: date)
        XCTAssertEqual(state.receive("What is ovulation?", now: date), .unrelated)
        XCTAssertEqual(state.receive("yes", now: date), .unrelated)
    }

    func testDateFollowUpRefinesFeelingWithoutSavingUntilConfirmation() {
        var state = LoggingConversation()
        XCTAssertEqual(state.receive("I'm feeling really tired today", now: date), .offer)
        guard case .dateRefined(let refined) = state.receive("Monday of this week", now: date) else {
            return XCTFail("A date answer should refine the pending feeling")
        }
        XCTAssertEqual(refined.text, "I'm feeling really tired today")
        XCTAssertEqual(refined.dateText, "Monday of this week")
        XCTAssertEqual(refined.resolvedDate, LogDate.parse("2026-10-19"))
        XCTAssertNil(refined.painRating)
        XCTAssertEqual(state.receive("Yes", now: date), .authorized(refined))
        XCTAssertEqual(LogAuthorization(text: "I feel tired", referenceDate: date, dateText: "October 19, 2026").resolvedDate,
                       LogDate.parse("2026-10-19"))
    }

    func testGenericConfirmationWithoutLogConsentStaysWithLatestConversation() {
        var state = LoggingConversation()
        XCTAssertEqual(state.receive("Can you tell me what to do today?", now: date), .unrelated)
        XCTAssertEqual(state.receive("Sure", now: date), .unrelated)
        XCTAssertEqual(state.receive("Monday of this week", now: date), .unrelated)
    }

    func testExistingBuiltinAndCustomTagsAreValidNotDuplicateCreationErrors() throws {
        XCTAssertEqual(try CompanionLogPatch.tag(" fatigue ", known: ["Fatigue"]), "Fatigue")
        XCTAssertEqual(try CompanionLogPatch.tag("TIRED", known: ["Tired"]), "Tired")
        XCTAssertEqual(try CompanionLogPatch.tag("joint pain", known: ["Joint pain"]), "Joint pain")
        XCTAssertEqual(try CompanionLogPatch.tag("dizzy", known: []), "Dizzy")
        XCTAssertThrowsError(try CompanionLogPatch.tag("  ", known: []))
        XCTAssertThrowsError(try CompanionLogPatch.tag(String(repeating: "x", count: 31), known: []))
    }

    func testMergingPreservesAllUnrelatedFieldsAndDoesNotInventRatings() throws {
        let old = DayLog(date: date, flow: "Heavy", moods: ["Calm"], symptoms: ["Cramps"], pain: 7, energy: 2, note: "Existing note")
        let patch = CompanionLogPatch(date: date, symptoms: ["Fatigue"], note: "I'm feeling really tired today")
        let saved = try patch.merged(with: old, today: date)
        XCTAssertEqual(saved.symptoms, ["Cramps", "Fatigue"])
        XCTAssertEqual(saved.moods, old.moods)
        XCTAssertEqual(saved.flow, old.flow)
        XCTAssertEqual(saved.pain, old.pain)
        XCTAssertEqual(saved.energy, old.energy)
        XCTAssertEqual(saved.note, "Existing note\nI'm feeling really tired today")
        XCTAssertEqual(try patch.merged(with: saved, today: date), saved)
        XCTAssertNil(patch.flow) // no implicit period end for a symptom-only log
        XCTAssertEqual(try patch.merged(with: nil, today: date).pain, 0) // existing schema's unspecified default
    }

    func testExplicitPainAndFlowOnly() {
        XCTAssertNil(LogAuthorization(text: "Log really bad cramps", referenceDate: date).painRating)
        XCTAssertEqual(LogAuthorization(text: "Log cramps, pain 6", referenceDate: date).painRating, 6)
        XCTAssertEqual(LogAuthorization(text: "Log pain 0/10", referenceDate: date).painRating, 0)
        XCTAssertNil(LogAuthorization(text: "Log fatigue at 6pm", referenceDate: date).painRating)
        XCTAssertEqual(LogAuthorization(text: "Log heavy flow today", referenceDate: date).flow, "Heavy")
        XCTAssertNil(LogAuthorization(text: "Log heavy cramps today", referenceDate: date).flow)
        XCTAssertTrue(LogAuthorization(text: "Log pain 11", referenceDate: date).hasInvalidPainRating)
        XCTAssertTrue(LogAuthorization(text: "Log pain 6.5/10", referenceDate: date).hasInvalidPainRating)
        XCTAssertTrue(LogAuthorization(text: "Log cramps on 2026-02-30", referenceDate: date).hasInvalidExplicitDate)
    }

    func testFalseSaveDefenseDoesNotRewriteOtherToolsOrEducation() {
        XCTAssertTrue(CompanionLogExecution.guardFalseSave("I'll log that you're tired today.").hasPrefix("I haven't saved"))
        XCTAssertTrue(CompanionLogExecution.guardFalseSave("I've recorded that.").hasPrefix("I haven't saved"))
        for text in ["I've saved your reminder.", "No saved entries in that range.", "Ovulation releases an egg [1].", "I haven't saved anything yet."] {
            XCTAssertEqual(CompanionLogExecution.guardFalseSave(text), text)
        }
    }

    func testStrictDatesLocalMidnightDSTAndValidation() throws {
        XCTAssertNil(LogDate.parse("2026-02-30"))
        XCTAssertNil(LogDate.parse("2026-2-03"))
        for zone in ["America/New_York", "Pacific/Auckland", "America/Los_Angeles"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let day = LogDate.parse("2026-03-08", calendar: calendar)!
            XCTAssertEqual(LogDate.key(day, calendar: calendar), "2026-03-08")
            XCTAssertEqual(calendar.component(.hour, from: day), 0)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
            XCTAssertThrowsError(try CompanionLogPatch(date: tomorrow, symptoms: ["Fatigue"]).merged(with: nil, today: day, calendar: calendar))
            let late = calendar.date(byAdding: .hour, value: 20, to: day)!
            XCTAssertEqual(try CompanionLogPatch(date: late, symptoms: ["Fatigue"]).merged(with: nil, today: late, calendar: calendar).date, day)
        }
        XCTAssertThrowsError(try CompanionLogPatch(date: date, pain: 11).merged(with: nil, today: date))
        XCTAssertThrowsError(try CompanionLogPatch(date: date, note: String(repeating: "x", count: 2001)).merged(with: nil, today: date))
    }

    @MainActor
    func testSaveAcknowledgementFailureAndRetryCannotDoubleWrite() async throws {
        let execution = CompanionLogExecution()
        let patch = CompanionLogPatch(date: date, symptoms: ["Fatigue"], note: "really tired")
        var writes = 0
        let result = await execution.save(patch) { request in
            writes += 1
            XCTAssertNil(execution.saved) // no confirmation before acknowledgement
            return try request.merged(with: nil, today: self.date)
        }
        XCTAssertEqual(result?.symptoms, ["Fatigue"])
        XCTAssertTrue(execution.message.hasPrefix("Saved your entry"))
        _ = await execution.save(patch) { _ in writes += 1; throw URLError(.badServerResponse) }
        XCTAssertEqual(writes, 1)
        XCTAssertNotNil(execution.saved) // a later model failure cannot erase the receipt

        let failed = CompanionLogExecution()
        _ = await failed.save(patch) { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertNil(failed.saved)
        XCTAssertTrue(failed.message.hasPrefix("Nothing was saved."))
        _ = await failed.save(patch) { _ in XCTFail("Must not retry a failed write implicitly"); return result! }
        XCTAssertNil(failed.saved)
    }

    @MainActor
    func testCommittedEntrySurvivesPersistenceRoundTripAndCalendarDayLookup() async throws {
        let patch = CompanionLogPatch(date: date, symptoms: ["Fatigue"], note: "really tired")
        let execution = CompanionLogExecution()
        var database: [String: Data] = [:]
        let committed = await execution.save(patch) { patch in
            let key = LogDate.key(patch.date)
            let existing = try database[key].map { try JSONDecoder().decode(DayLog.self, from: $0) }
            let merged = try patch.merged(with: existing, today: self.date)
            database[key] = try JSONEncoder().encode(merged)
            return merged
        }
        let reloaded = try JSONDecoder().decode(DayLog.self, from: XCTUnwrap(database["2026-10-20"]))
        XCTAssertEqual(reloaded, committed)
        XCTAssertTrue(LogDate.calendar.isDate(reloaded.date, inSameDayAs: date))
        XCTAssertEqual(reloaded.symptoms, ["Fatigue"])
    }
}
