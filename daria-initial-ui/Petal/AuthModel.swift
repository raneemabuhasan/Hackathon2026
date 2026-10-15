import SwiftUI
import Observation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

/// Who is signed in, and the ways to sign in. Supports email/password and Google.
/// Sign in with Apple needs a paid Apple Developer account, so it is not wired up yet.
@MainActor @Observable
final class AuthModel {
    private(set) var user: User?
    /// False until Firebase has restored any saved session, so we don't flash the sign-in screen.
    private(set) var ready = false
    var busy = false
    var error: String?

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.ready = true
        }
    }

    // MARK: Email

    func signIn(email: String, password: String) async {
        await run { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    func signUp(name: String, email: String, password: String) async {
        await run {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            self.user = Auth.auth().currentUser
        }
    }

    func resetPassword(email: String) async {
        await run {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            self.error = "Check your inbox for a reset link."
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        await run {
            guard let clientID = FirebaseApp.app()?.options.clientID else { throw AuthError.missingClientID }
            guard let root = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
            else { return }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let idToken = result.user.idToken?.tokenString else { throw AuthError.missingToken }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: result.user.accessToken.tokenString)
            _ = try await Auth.auth().signIn(with: credential)
        }
    }

    // MARK: Sign out

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch let e as GIDSignInError where e.code == .canceled {
            // User closed the Google sheet; nothing to report.
        } catch {
            self.error = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        guard let code = AuthErrorCode(rawValue: (error as NSError).code) else { return error.localizedDescription }
        switch code {
        case .invalidEmail: return "That email address doesn't look right."
        case .emailAlreadyInUse: return "There's already an account with that email. Try signing in."
        case .weakPassword: return "Choose a password with at least 6 characters."
        case .wrongPassword, .invalidCredential, .userNotFound: return "Email or password is incorrect."
        case .networkError: return "Couldn't reach the server. Check your connection."
        case .accountExistsWithDifferentCredential: return "This email is already linked to another sign-in method."
        default: return error.localizedDescription
        }
    }

    enum AuthError: LocalizedError {
        case missingClientID, missingToken
        var errorDescription: String? {
            switch self {
            case .missingClientID: "Google sign-in isn't configured (no CLIENT_ID in GoogleService-Info.plist)."
            case .missingToken: "Google didn't return a sign-in token. Please try again."
            }
        }
    }
}
