import SwiftUI
import Lottie

struct SignInView: View {
    @Environment(AuthModel.self) private var auth
    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    // Sign-in checks only the length so accounts made under older rules can still sign in.
    private var passwordOK: Bool {
        creating ? PasswordRequirement.allMet(password) : password.count >= PasswordRequirement.minLength
    }

    private var canSubmit: Bool {
        !email.isEmpty && passwordOK && (!creating || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("SyncWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
                    .padding(.top, 56)
                    .accessibilityLabel("Sync")

                LottieView(animation: .named("signin"))
                    .looping()
                    .resizable()
                    .scaledToFit()
                    .frame(height: creating ? 140 : 175)
                    .accessibilityHidden(true)

                VStack(spacing: 14) {
                    Button { Task { await auth.signInWithGoogle() } } label: {
                        HStack(spacing: 10) {
                            Text("G").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Palette.accent)
                            Text("Continue with Google").font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Rectangle().fill(Palette.line).frame(height: 1)
                        Text("or with email").font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }

                    if creating {
                        field("First name", text: $name).textContentType(.givenName)
                    }
                    field("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    field("Password", text: $password, secure: true)
                        .textContentType(creating ? .newPassword : .password)

                    if creating {
                        PasswordChecklist(password: password)
                            .transition(.opacity)
                    }

                    if let error = auth.error {
                        Text(error).font(.system(size: 13)).foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        Group {
                            if auth.busy { ProgressView().tint(.white) }
                            else { Text(creating ? "Create account" : "Sign in").font(.system(size: 16, weight: .semibold)) }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(canSubmit ? 1 : 0.4), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || auth.busy)

                    if !creating {
                        Button("Forgot password?") { Task { await auth.resetPassword(email: email) } }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .disabled(email.isEmpty)
                    }

                    Text("Only you can read your logs. Nothing is shared or sold.")
                        .font(.caption).foregroundStyle(Palette.inkFaint)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Text(creating ? "Already have an account?" : "Don't have an account?")
                    .foregroundStyle(Palette.inkSoft)
                Button(creating ? "Sign in" : "Create one") {
                    creating.toggle()
                    auth.error = nil
                }
                .fontWeight(.semibold)
                .foregroundStyle(Palette.accent)
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.cream.opacity(0.9))
        }
        .background(
            RadialGradient(colors: [Palette.blush, Palette.mist, Palette.cream], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: creating)
    }

    private func submit() {
        Task {
            if creating {
                await auth.signUp(name: name.trimmingCharacters(in: .whitespaces), email: email, password: password)
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line))
    }
}

/// Live sign-up password rules; collapses to one line once every rule passes.
private struct PasswordChecklist: View {
    let password: String

    var body: some View {
        let allMet = PasswordRequirement.allMet(password)
        VStack(alignment: .leading, spacing: 6) {
            if allMet {
                row("Password looks good", met: true, spoken: "Password looks good, all requirements met")
            } else {
                ForEach(PasswordRequirement.all) { requirement in
                    let met = requirement.isMet(password)
                    row(requirement.label, met: met, spoken: "\(requirement.label), \(met ? "met" : "not met")")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.15), value: allMet)
    }

    private func row(_ label: String, met: Bool, spoken: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? Palette.success : Palette.inkFaint)
                .contentTransition(.symbolEffect(.replace))
            Text(label)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .animation(.easeOut(duration: 0.15), value: met)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
