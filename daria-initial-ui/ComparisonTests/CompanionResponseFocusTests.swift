import XCTest
@testable import PetalComparison

final class CompanionResponseFocusTests: XCTestCase {
    func testExactScreenshotFoodQuestionRoutesToNutrition() {
        let focus = CompanionResponseFocus(message: "Is there something I can eat to help me during this cycle ?")
        XCTAssertTrue(focus.wantsMealIdeas)
        XCTAssertTrue(EducationLibrary.requiresEducation("Is there something I can eat to help me during this cycle ?"))
        for prompt in ["What could I eat?", "Any meal ideas for today?", "Suggest a snack", "What foods are good during my period?"] {
            XCTAssertTrue(CompanionResponseFocus(message: prompt).wantsMealIdeas, prompt)
        }
    }

    func testFoodHistoryLoggingRemindersAndDefinitionsKeepExistingRoutes() {
        for prompt in ["What is PMS?", "What did I eat last week?", "Show my logged meals", "Log what I ate today", "Remind me to eat lunch", "Save this recipe", "Does food balance hormones?", "Can food cure PCOS?", "What is a food allergy?", "The food was great"] {
            XCTAssertFalse(CompanionResponseFocus(message: prompt).wantsMealIdeas, prompt)
        }
    }

    func testPMSThenFoodRejectsFreshlyCitedButWrongTopicAnswer() throws {
        let library = try EducationLibrary.bundled()
        let focus = CompanionResponseFocus(message: "Is there something I can eat to help me during this cycle ?")
        var evidence = EducationEvidence()
        evidence.record(library.get(.nutrition))
        // Even if the model retrieves PMS again, valid provenance alone isn't a relevant answer.
        evidence.record(library.get(.pms))
        let stale = try evidence.validate("PMS refers to symptoms before a period [edu:nhs-pms].", library: library, required: true)
        XCTAssertFalse(focus.accepts(stale, previousAnswer: "What is PMS?"))
        let food = try evidence.validate("An optional idea is a lentil meal [edu:nutrition-menstrual]. Phase-specific benefits are unproven [edu:syncing-evidence].", library: library, required: true)
        XCTAssertTrue(focus.accepts(food, previousAnswer: stale.text))
        XCTAssertFalse(focus.accepts(food, previousAnswer: food.text))
        XCTAssertEqual(food.citations.map(\.sourceID), ["cc-cycle-syncing", "cc-cycle-syncing"])
    }

    func testPreviousNumericCitationsCannotPassAfterNutritionPreparation() throws {
        let library = try EducationLibrary.bundled()
        var evidence = EducationEvidence()
        evidence.record(library.get(.nutrition))
        XCTAssertThrowsError(try evidence.validate("PMS means premenstrual syndrome [1].", library: library, required: true))
        XCTAssertThrowsError(try evidence.validate("PMS means symptoms before a period [edu:nhs-pms].", library: library, required: true))
    }

    func testUnrelatedRepliesAndHonestUnsupportedAnswerAreNotRejected() {
        let pms = CompanionResponseFocus(message: "What is PMS?")
        let answer = EducationAnswer(text: "An explanation.", citations: [])
        XCTAssertTrue(pms.accepts(answer, previousAnswer: answer.text))
        let food = CompanionResponseFocus(message: "What should I eat?")
        XCTAssertTrue(food.accepts(EducationAnswer(text: EducationEvidence.unsupported, citations: []), previousAnswer: nil))
    }
}
