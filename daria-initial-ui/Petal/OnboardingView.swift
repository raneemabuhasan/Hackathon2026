import SwiftUI

/// First-run questions so predictions work before any cycles have been logged.
struct OnboardingView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @State private var name = ""
    @State private var lastStart = CycleStore.add(.now, -10)
    @State private var cycleLength = 28
    @State private var periodLength = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "A few quick questions")
                    DisplayTitle(before: "Tell us about ", accent: "your cycle")
                    Text("Rough answers are fine. Petal learns from what you log and gets more accurate over time.")
                        .font(.system(size: 14)).foregroundStyle(Palette.inkSoft)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    row("What should we call you?") {
                        TextField("First name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textContentType(.givenName)
                    }
                    Divider().overlay(Palette.line)
                    row("When did your last period start?") {
                        DatePicker("", selection: $lastStart, in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Divider().overlay(Palette.line)
                    row("Usual cycle length") {
                        Stepper("\(cycleLength) days", value: $cycleLength, in: 18...45).fixedSize()
                    }
                    Divider().overlay(Palette.line)
                    row("Usual period length") {
                        Stepper("\(periodLength) days", value: $periodLength, in: 2...10).fixedSize()
                    }
                }
                .font(.system(size: 14))
                .card()

                Button {
                    store.completeOnboarding(name: name.trimmingCharacters(in: .whitespaces), lastPeriodStart: lastStart,
                                             cycleLength: cycleLength, periodLength: periodLength)
                } label: {
                    Text("Start tracking")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(name.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Sign out") { auth.signOut() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .onAppear {
            if name.isEmpty, let full = auth.user?.displayName {
                name = full.components(separatedBy: " ").first ?? full
            }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 12)
            content()
        }
    }
}
