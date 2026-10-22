import Foundation

/// The single list of sign-up password rules. The checklist and the submit button both read it,
/// so a new rule changes the UI and the button together. Keep it in line with Firebase's policy.
struct PasswordRequirement: Identifiable {
    let id: String
    let label: String
    let isMet: (String) -> Bool

    /// Firebase Auth's default minimum. Sign-in checks only this, never the full list.
    static let minLength = 6

    static let all: [PasswordRequirement] = [
        PasswordRequirement(id: "length", label: "At least \(minLength) characters") { $0.count >= minLength }
    ]

    static func allMet(_ password: String) -> Bool {
        all.allSatisfy { $0.isMet(password) }
    }
}
