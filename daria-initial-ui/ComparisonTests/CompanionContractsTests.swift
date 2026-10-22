import XCTest
@testable import PetalComparison

final class CompanionContractsTests: XCTestCase {
    let today = LogDate.parse("2026-10-21")!

    func testTimeEditPreservesScheduleIdentityPreferencesAndDormantFields() throws {
        let original = Reminder(id: "server-id", title: "Evening check-in", kind: .beforePeriod,
            hour: 20, minute: 30, date: today, daysBefore: 5, on: false, created: today)
        let changed = try ReminderPatch(time: "21:00").applying(to: original, today: today)
        XCTAssertEqual(changed.id, original.id)
        XCTAssertEqual(changed.title, original.title)
        XCTAssertEqual(changed.kind, original.kind)
        XCTAssertEqual(changed.daysBefore, 5)
        XCTAssertEqual(changed.date, original.date)
        XCTAssertEqual(changed.created, original.created)
        XCTAssertFalse(changed.on)
        XCTAssertEqual(changed.hour, 21)
        XCTAssertEqual(changed.minute, 0)
    }

    func testStopIsPauseAndExpiredOnceCanBeDisabled() throws {
        let old = LogDate.parse("2026-10-20")!
        let original = Reminder(title: "Water", kind: .once, hour: 9, minute: 0, date: old)
        let paused = try ReminderPatch(enabled: false).applying(to: original, today: today)
        XCTAssertFalse(paused.on)
        XCTAssertEqual(paused.date, old)
        XCTAssertFalse(CompanionIntent.explicitDeletion("Stop my water reminder"))
        XCTAssertTrue(CompanionIntent.reminderChange("Stop my water reminder"))
        XCTAssertTrue(CompanionIntent.explicitDeletion("Delete my water reminder"))
        XCTAssertFalse(CompanionIntent.explicitDeletion("Don't delete my water reminder"))
    }

    func testMalformedAndIncompleteEditsDoNotReachWriteBoundary() throws {
        let original = Reminder(title: "Water", kind: .daily, hour: 9, minute: 0)
        for patch in [ReminderPatch(), ReminderPatch(time: "9:00"), ReminderPatch(time: "24:00"),
                      ReminderPatch(time: "21:60"), ReminderPatch(title: "  "),
                      ReminderPatch(schedule: "weekly"), ReminderPatch(schedule: "once"),
                      ReminderPatch(schedule: "before_period"), ReminderPatch(date: "2026-02-30"),
                      ReminderPatch(daysBefore: 8), ReminderPatch(date: "2026-10-22")] {
            XCTAssertThrowsError(try patch.applying(to: original, today: today))
        }
        let once = try ReminderPatch(schedule: "once", date: "2026-10-22").applying(to: original, today: today)
        XCTAssertEqual(once.kind, .once)
        XCTAssertEqual(once.date, LogDate.parse("2026-10-22"))
    }

    func testDeletionConsentIsOneUseAndCannotCrossTopicOrLogging() {
        var consent = ReminderDeletionConsent()
        XCTAssertNil(consent.consume("yes"))
        consent.stage(id: "water", title: "Water")
        XCTAssertEqual(consent.consume("Yes please"), "water")
        XCTAssertNil(consent.consume("yes"))
        consent.stage(id: "water", title: "Water")
        XCTAssertNil(consent.consume("Why do I feel tired?"))
        XCTAssertNil(consent.consume("Sure"))
        consent.stage(id: "water", title: "Water")
        XCTAssertNil(consent.consume("yes, log it"))
        XCTAssertNil(consent.consume("yes"))
    }

    func testNoConsentCanBeInferredFromToolGeneratedText() {
        XCTAssertFalse(CompanionIntent.reminderCreation("Sure"))
        XCTAssertFalse(CompanionIntent.reminderCreation("What reminders do I have?"))
        XCTAssertFalse(CompanionIntent.reminderCreation("Don't remind me"))
        XCTAssertTrue(CompanionIntent.reminderCreation("Remind me to drink water at 2pm"))
    }

    func testAmbiguousReminderNamesCannotBeGuessed() {
        let morning = Reminder(id: "am", title: "Morning check-in", kind: .daily, hour: 9, minute: 0)
        let evening = Reminder(id: "pm", title: "Evening check-in", kind: .daily, hour: 20, minute: 0)
        let all = [morning, evening]
        XCTAssertFalse(ReminderSelection.allows(id: "am", in: all, request: "Move my check-in to 9pm"))
        XCTAssertTrue(ReminderSelection.allows(id: "pm", in: all, request: "Move my evening check-in to 9pm"))
        XCTAssertFalse(ReminderSelection.allows(id: "am", in: all, request: "Move my evening check-in to 9pm"))
        XCTAssertFalse(ReminderSelection.allows(id: "guessed", in: all, request: "Move my evening check-in to 9pm"))
        XCTAssertFalse(ReminderSelection.allows(id: "am", in: [morning, morning], request: "Delete my morning check-in"))
    }

    func testReminderClarificationRetainsChangeButNeverSurvivesTopicSwitch() {
        let all = [Reminder(id: "am", title: "Morning check-in", kind: .daily, hour: 9, minute: 0),
                   Reminder(id: "pm", title: "Evening check-in", kind: .daily, hour: 20, minute: 0)]
        var clarification = ReminderClarification()
        clarification.stage("Move my check-in to 9pm")
        let request = clarification.consume("Evening", reminders: all)!
        XCTAssertTrue(CompanionIntent.reminderChange(request))
        XCTAssertTrue(ReminderSelection.allows(id: "pm", in: all, request: request))
        XCTAssertNil(clarification.consume("Evening", reminders: all))
        clarification.stage("Delete my check-in")
        XCTAssertNil(clarification.consume("Explain why I feel tired", reminders: all))
        XCTAssertNil(clarification.consume("Evening", reminders: all))
        clarification.stage("Delete my check-in")
        XCTAssertNil(clarification.consume("Sure", reminders: all))
    }

    func testValidAndMalformedPlanCards() {
        XCTAssertTrue(CardValidation.plan(icon: "leaf", title: "A gentle walk", detail: "Try it if it feels comfortable."))
        XCTAssertFalse(CardValidation.plan(icon: "invented", title: "Walk", detail: "Optional."))
        XCTAssertFalse(CardValidation.plan(icon: "leaf", title: " ", detail: "Optional."))
        XCTAssertFalse(CardValidation.plan(icon: "leaf", title: "Walk", detail: ""))
        XCTAssertFalse(CardValidation.plan(icon: "leaf", title: "one two three four five six seven", detail: "Optional."))
    }

    func testRecipesRejectMissingStepsUnknownEnumsAndInvalidNumbers() {
        func valid(minutes: Int? = 20, diets: [String] = ["vegan"], allergens: [String] = [], steps: [String] = ["Prepare.", "Cook.", "Serve."]) -> Bool {
            CardValidation.meal(name: "Lentil bowl", why: "A balanced meal idea.", minutes: minutes, servings: 2,
                diets: diets, allergens: allergens, ingredients: ["200 g lentils"], shopping: ["Lentils", "Rice", "Spinach"], steps: steps)
        }
        XCTAssertTrue(valid())
        XCTAssertFalse(valid(minutes: nil))
        XCTAssertFalse(valid(minutes: -1))
        XCTAssertFalse(valid(minutes: 46))
        XCTAssertFalse(valid(diets: ["hormone-balancing"]))
        XCTAssertFalse(valid(allergens: ["unknown"]))
        XCTAssertFalse(valid(steps: []))
        XCTAssertFalse(valid(steps: ["", "Cook.", "Serve."]))
    }

    func testDeclineLoggingThenExplainStaysEducation() throws {
        var logs = LoggingConversation()
        XCTAssertEqual(logs.receive("I feel tired", now: today), .offer)
        XCTAssertEqual(logs.receive("No, don't log it; explain why I might feel tired", now: today), .unrelated)
        XCTAssertNil(logs.pending)
        let library = try EducationLibrary.bundled()
        var evidence = EducationEvidence()
        evidence.record(library.get(.fatigue))
        let answer = try evidence.validate("Sleep and stress can contribute to tiredness [edu:nhs-fatigue]. PMS can include tiredness and irritability [edu:nhs-pms].", library: library, required: true)
        XCTAssertEqual(answer.citations.count, 2)
        XCTAssertEqual(library.suggestedPrompts(for: answer.citations).count, 3)
        XCTAssertFalse(answer.text.contains("bundled"))
    }

    func testEveryEducationTopicHasControlledSourcesAndUnsupportedFailsKindly() throws {
        let library = try EducationLibrary.bundled()
        for topic in EducationTopic.allCases where topic != .unsupported {
            let passages = library.get(topic)
            XCTAssertFalse(passages.isEmpty, topic.rawValue)
            var evidence = EducationEvidence()
            evidence.record(passages)
            let answer = try evidence.validate("General explanation [edu:\(passages[0].id)].", library: library, required: true)
            XCTAssertEqual(answer.citations.count, 1)
            XCTAssertTrue(EducationLibrary.allowedURLs.contains(answer.citations[0].url.absoluteString))
        }
        var empty = EducationEvidence()
        empty.record(library.get(.unsupported))
        let answer = try empty.validate("[education:unsupported]", library: library, required: true)
        XCTAssertTrue(answer.citations.isEmpty)
        XCTAssertFalse(answer.text.contains("library"))
        XCTAssertFalse(answer.text.contains("passage"))
        XCTAssertTrue(library.suggestedPrompts(for: []).isEmpty)
    }
}
