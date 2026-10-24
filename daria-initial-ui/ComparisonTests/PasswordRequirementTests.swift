import XCTest
@testable import PetalComparison

final class PasswordRequirementTests: XCTestCase {
    private var length: PasswordRequirement {
        PasswordRequirement.all.first { $0.id == "length" }!
    }

    func testLengthRuleMatchesFirebaseMinimum() {
        XCTAssertEqual(PasswordRequirement.minLength, 6)
        XCTAssertEqual(length.label, "At least 6 characters")
    }

    func testShortPasswordsAreUnmet() {
        XCTAssertFalse(length.isMet(""))
        XCTAssertFalse(length.isMet("abcde"))
        XCTAssertFalse(PasswordRequirement.allMet("abcde"))
    }

    func testSixthCharacterMeetsRule() {
        XCTAssertTrue(length.isMet("abcdef"))
        XCTAssertTrue(PasswordRequirement.allMet("abcdef"))
    }

    func testDeletingCharactersUnmetsRule() {
        var password = "abcdef"
        XCTAssertTrue(PasswordRequirement.allMet(password))
        password.removeLast()
        XCTAssertFalse(PasswordRequirement.allMet(password))
    }

    func testCountsCharactersNotBytes() {
        // Same counting as String.count: each emoji and combined character is one character.
        XCTAssertFalse(length.isMet("👩‍👩‍👧‍👦é🌸🌸🌸"))
        XCTAssertTrue(length.isMet("👩‍👩‍👧‍👦é🌸🌸🌸🌸"))
    }

    func testIOSStrongPasswordSatisfiesEveryRule() {
        XCTAssertTrue(PasswordRequirement.allMet("xemvo3-kubqUj-fizpyt"))
    }

    func testAllMetMatchesEveryRule() {
        for password in ["", "a", "abcde", "abcdef", "abcdefghijkl"] {
            XCTAssertEqual(PasswordRequirement.allMet(password),
                           PasswordRequirement.all.allSatisfy { $0.isMet(password) })
        }
    }
}
