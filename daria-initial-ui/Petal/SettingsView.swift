import SwiftUI

/// Personal settings, opened from the initial in the top corner of Today.
struct SettingsView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var lastStart = Date.now
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var confirmingDelete = false
    @State private var confirmingAccountDelete = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmingSignOut = false


    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var usesPassword: Bool { auth.user?.providerData.contains { $0.providerID == "password" } ?? false }

    private var changed: Bool {
        guard let p = store.profile else { return false }
        return trimmedName != p.name || cycleLength != p.cycleLength || periodLength != p.periodLength
            || !CycleStore.cal.isDate(lastStart, inSameDayAs: store.periodHistory.records.map(\.start).max() ?? p.lastPeriodStart)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Eyebrow(text: "Settings")
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(trimmedName.isEmpty ? "You" : trimmedName).font(.display(28))
                    if let email = auth.user?.email {
                        Text(email).font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                    }
                }

                section("Profile") {
                    TextField("First name", text: $name)
                        .textContentType(.givenName)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                section("Your cycle") {
                    VStack(spacing: 12) {
                        DatePicker("Last period started", selection: $lastStart, in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                        Divider().overlay(Palette.line)
                        stepper("Usual cycle length", value: $cycleLength, range: 18...45)
                        Divider().overlay(Palette.line)
                        stepper("Usual period length", value: $periodLength, range: 2...10)
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSoft)
                }

                Button {
                    saving = true
                    saveError = nil
                    Task {
                        defer { saving = false }
                        do {
                            try await store.updateProfile(name: trimmedName, lastPeriodStart: lastStart,
                                                          cycleLength: cycleLength, periodLength: periodLength)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                } label: {
                    Text(saving ? "Saving…" : "Save changes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(changed && !trimmedName.isEmpty ? 1 : 0.4), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saving || !changed || trimmedName.isEmpty)

                if let saveError {
                    Text(saveError)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.wine)
                }

                section("Account") {
                    VStack(alignment: .leading, spacing: 12) {
                        if usesPassword, let email = auth.user?.email {
                            row("Change password", icon: "key") {
                                Task { await auth.resetPassword(email: email) }
                            }
                            if let message = auth.error {
                                Text(message).font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                            }
                            Divider().overlay(Palette.line)
                        }
                        row("Sign out", icon: "rectangle.portrait.and.arrow.right") {
                            confirmingSignOut = true
                        }
                    }
                }

                section("Your data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your logs are stored in your private account and only you can read them. Nothing is shared or sold.")
                            .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        outlineButton("Delete all my data") { confirmingDelete = true }
                        outlineButton("Delete account") { confirmingAccountDelete = true }
                        if let message = auth.error {
                            Text(message).font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .alert("Are you sure you want to sign out?", isPresented: $confirmingSignOut) {
            Button("Sign out", role: .destructive) {
                dismiss()
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data stays saved in your account. Sign back in any time to pick up where you left off.")
        }
        .alert("Are you sure you want to delete all your data?", isPresented: $confirmingDelete) {
            Button("Delete my data", role: .destructive) {
                Task {
                    do {
                        try await store.deleteAllData()
                        dismiss()
                    } catch { store.showToast("Couldn't delete your data: \(error.localizedDescription)") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases every log, period, reminder and preference in your account. Your account stays so you can start fresh. This can't be undone.")
        }
        .alert("Are you sure you want to delete your account?", isPresented: $confirmingAccountDelete) {
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount(store) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases all your data and your sign-in. Google users will be asked to confirm with Google. This can't be undone.")
        }
        .onAppear {
            auth.error = nil
            guard let p = store.profile else { return }
            name = p.name
            lastStart = store.periodHistory.records.map(\.start).max() ?? p.lastPeriodStart
            cycleLength = p.cycleLength
            periodLength = p.periodLength
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .card()
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) days").fontWeight(.semibold).foregroundStyle(Palette.ink).monospacedDigit()
            }
        }
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 22)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(Capsule().stroke(Palette.rose.opacity(0.3)))
            .buttonStyle(.plain)
    }
}
