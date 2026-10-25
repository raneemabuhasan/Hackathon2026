import XCTest
@testable import PetalComparison

final class CompanionContractsTests: XCTestCase {
    let today = LogDate.parse("2026-10-21")!

    func testArithmeticQuestionsAreBlockedWithoutMatchingCycleNumbers() {
        for prompt in ["5+10", "What is 5 + 10?", "Can you tell me what is 5 plus 10?", "calculate 5 * 10",
                       "What is five plus ten?", "What is (5 + 10) * 2?", "5 + 10, then tell me a joke", "Please solve 5+10 and write code"] {
            XCTAssertTrue(CompanionIntent.isArithmeticQuestion(prompt), prompt)
        }
        for prompt in ["What cycle day am I on?", "I logged 5 symptoms over 10 days", "My period lasted from day 5 to day 10",
                       "I logged my period on 2026-10-01", "How many days since my last period on 2026-10-01?", "My period started on 10/01/2026",
                       "Is a 21-35 day cycle normal?", "I bleed for 3-7 days, is that ok?", "My cycles are between 26 and 32 days",
                       "I took 2 x 200mg ibuprofen", "Should I take 1/2 a pill?"] {
            XCTAssertFalse(CompanionIntent.isArithmeticQuestion(prompt), prompt)
        }
    }

    func testCompanionScopeBlocksUnrelatedRequestsAndUsesShortFollowUps() {
        XCTAssertEqual(CompanionIntent.companionScope("Write a Python program to track my cycle"), .redirect)
        XCTAssertEqual(CompanionIntent.companionScope("What is the capital of France?"), .redirect)
        XCTAssertEqual(CompanionIntent.companionScope("What's the weather, and what phase am I in?"), .redirect)
        XCTAssertEqual(CompanionIntent.companionScope("What can a doctor do?"), .redirect)
        XCTAssertEqual(CompanionIntent.companionScope("Should I see a doctor?", previousUserRequest: "Why do I feel tired before my period?"), .inScope)
        XCTAssertTrue(CompanionIntent.containsExplicitUnrelatedRequest("Log my symptoms and tell me a joke"))
        XCTAssertEqual(CompanionIntent.companionScope("How many days since my last period?"), .inScope)
        XCTAssertEqual(CompanionIntent.companionScope("What about food?", previousUserRequest: "Why do I feel tired before my period?"), .inScope)
        XCTAssertEqual(CompanionIntent.companionScope("What is five plus ten?", previousUserRequest: "Why do I feel tired?"), .redirect)
        XCTAssertEqual(CompanionIntent.companionScope("Hi"), .clarify)
        for prompt in ["Am I pregnant?", "Is it normal to feel sad?", "I struggle with body image before my period",
                       "My IUD is making me anxious", "Does the implant stop bleeding?"] {
            XCTAssertEqual(CompanionIntent.companionScope(prompt), .inScope, prompt)
        }
    }

    func testUnsupportedMedicalClaimsAreFlagged() {
        for answer in ["You have PCOS.", "You are still protected from pregnancy.", "Double your pill dose.",
                       "These foods balance hormones.", "This diet can treat cramps."] {
            XCTAssertTrue(CompanionAnswerSafety.hasUnsupportedClaim(answer), answer)
        }
        for answer in ["I can’t diagnose PCOS.", "Some people find warm meals comforting.", "Ask your clinician before changing medication.",
                       "You can take ibuprofen for cramps.", "Don't stop taking your pill without asking your doctor."] {
            XCTAssertFalse(CompanionAnswerSafety.hasUnsupportedClaim(answer), answer)
        }
    }

    func testPersonalDatesAndDurationsRequireReadOnlyEvidence() {
        XCTAssertTrue(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your next period is 2026-11-02.", evidence: "nextPeriod: 2026-11-01"))
        XCTAssertFalse(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your next period is 2026-11-02.", evidence: "nextPeriod: 2026-11-02"))
        XCTAssertTrue(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your next period is November 2, 2026.", evidence: "nextPeriod: 2026-11-01"))
        XCTAssertFalse(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your next period is November 2, 2026.", evidence: "nextPeriod: 2026-11-02"))
        XCTAssertTrue(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your average cycle is 31 days.", evidence: "averageCycleLength: 30"))
        XCTAssertFalse(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your average cycle is 31 days.", evidence: "averageCycleLength: 31"))
        XCTAssertFalse(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Many cycles vary from month to month.", evidence: ""))
        XCTAssertFalse(CompanionAnswerSafety.hasUnverifiedPersonalFacts("Your period usually lasts 3 to 7 days.", evidence: ""))
        XCTAssertTrue(CompanionAnswerSafety.hasUnverifiedPersonalFacts("You're on cycle day 12.", evidence: "cycleDay: 11"))
        XCTAssertFalse(CompanionAnswerSafety.hasUnverifiedPersonalFacts("You're on cycle day 12.", evidence: "cycleDay: 12"))
    }

    func testSelectedWeekdaysPersistAndGenerateRepeatingCalendarTimes() throws {
        let reminder = Reminder(title: "Take birth control", kind: .daily, hour: 9, minute: 15,
                                weekdays: [1, 3, 4, 7, 3, 0, 8])
        let decoded = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder))
        XCTAssertEqual(decoded.repeatWeekdays, [3, 4, 7, 1])
        XCTAssertEqual(decoded.dailyNotificationComponents.map(\.weekday), [3, 4, 7, 1])
        XCTAssertTrue(decoded.dailyNotificationComponents.allSatisfy { $0.hour == 9 && $0.minute == 15 })
        let changed = try ReminderPatch(time: "10:30").applying(to: decoded, today: today)
        XCTAssertEqual(changed.repeatWeekdays, decoded.repeatWeekdays)
        XCTAssertTrue(changed.dailyNotificationComponents.allSatisfy { $0.hour == 10 && $0.minute == 30 })
    }

    func testLegacyDailyReminderStillSchedulesEveryDay() throws {
        let old = Reminder(title: "Water", kind: .daily, hour: 14, minute: 0)
        let decoded = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.weekdays)
        XCTAssertEqual(decoded.dailyNotificationComponents.count, 1)
        XCTAssertNil(decoded.dailyNotificationComponents.first?.weekday)
        var selected = old
        selected.weekdays = [2, 4]
        let daily = try ReminderPatch(schedule: "daily").applying(to: selected, today: today)
        XCTAssertNil(daily.weekdays)
        selected.weekdays = []
        XCTAssertTrue(selected.dailyNotificationComponents.isEmpty)
    }

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
