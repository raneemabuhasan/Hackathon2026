import SwiftUI

/// First-run questions so predictions work before any cycles have been logged.
struct OnboardingView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @State private var name = ""
    @State private var lastStart = CycleStore.add(.now, -10)
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    DisplayTitle(before: "Tell us about ", accent: "your cycle", size: 32)
                        .multilineTextAlignment(.center)
                    Text("Rough answers are fine. Sync learns from what you log and gets more accurate over time.")
                        .font(.system(size: 14)).foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 56)
                .padding(.bottom, 12)

                question("What should we call you?") {
                    TextField("First name", text: $name)
                        .textContentType(.givenName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                question("When did your last period start?") {
                    DatePicker("Start date", selection: $lastStart, in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkSoft)
                }

                question("What's usual for you?") {
                    VStack(spacing: 12) {
                        stepper("Cycle length", value: $cycleLength, range: 18...45)
                        Divider().overlay(Palette.line)
                        stepper("Period length", value: $periodLength, range: 2...10)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    store.completeOnboarding(name: trimmedName, lastPeriodStart: lastStart,
                                             cycleLength: cycleLength, periodLength: periodLength)
                } label: {
                    Text("Start tracking")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(trimmedName.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmedName.isEmpty)

                HStack(spacing: 4) {
                    Text("Not you?").foregroundStyle(Palette.inkSoft)
                    Button("Sign out") { auth.signOut() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.accent)
                }
                .font(.system(size: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Palette.cream.opacity(0.9))
        }
        .background(
            RadialGradient(colors: [Palette.blush, Palette.mist, Palette.cream], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea())
        .onAppear {
            if name.isEmpty, let full = auth.user?.displayName {
                name = full.components(separatedBy: " ").first ?? full
            }
        }
    }

    private func question<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .card()
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title).font(.system(size: 14)).foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("\(value.wrappedValue) days").font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
        }
    }
}
