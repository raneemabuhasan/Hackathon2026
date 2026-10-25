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
    @State private var method: BirthControl.Method?
    @State private var packStart = Date.now
    @State private var activeDays: Int? = 21
    @State private var confirmingDelete = false
    @State private var confirmingAccountDelete = false
    @State private var deletePassword = ""
    @State private var confirmingSignOut = false
    @AppStorage("sync.floatingRobot.enabled") private var floatingRobotEnabled = false
    @State private var placement = FloatingRobotPlacement.shared

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var usesPassword: Bool { auth.user?.providerData.contains { $0.providerID == "password" } ?? false }

    private var birthControl: BirthControl? {
        method.map { m in
            m.hasSchedule ? BirthControl(method: m, packStart: CycleStore.cal.startOfDay(for: packStart), activeDays: activeDays)
                          : BirthControl(method: m)
        }
    }

    private var changed: Bool {
        guard let p = store.profile else { return false }
        return birthControl != p.birthControl || trimmedName != p.name || cycleLength != p.cycleLength || periodLength != p.periodLength
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

                section("Birth control") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Method") {
                            Picker("Method", selection: Binding(get: { method }, set: { picked in
                                method = picked
                                if let picked, !picked.hasSchedule || (picked != .combinedPill && activeDays == 24) { activeDays = 21 }
                            })) {
                                Text("None").tag(BirthControl.Method?.none)
                                ForEach(BirthControl.Method.allCases) { Text($0.name).tag(Optional($0)) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        if let method, method.hasSchedule {
                            Divider().overlay(Palette.line)
                            DatePicker("Current \(method.scheduleNoun) started", selection: $packStart,
                                       in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                            Divider().overlay(Palette.line)
                            LabeledContent("Breaks") {
                                Picker("Breaks", selection: $activeDays) {
                                    ForEach(birthControl?.regimens ?? [], id: \.label) { Text($0.label).tag($0.days) }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                        Text("Hormonal methods usually pause ovulation, so Sync hides cycle phases and predicts bleeds from your schedule, or not at all. Pill and patch reminders are in your reminders list.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSoft)
                }

                Button {
                    if birthControl != store.profile?.birthControl { store.saveBirthControl(birthControl) }
                    store.updateProfile(name: trimmedName, lastPeriodStart: lastStart,
                                        cycleLength: cycleLength, periodLength: periodLength)
                    dismiss()
                } label: {
                    // Say why it's disabled instead of just fading out.
                    Text(trimmedName.isEmpty ? "Add your name to save" : changed ? "Save changes" : "No changes to save")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(changed && !trimmedName.isEmpty ? 1 : 0.4), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!changed || trimmedName.isEmpty)

                section("Appearance") {
                    Text("Choose your colors")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                    Text("Text, backgrounds and accents change together. Saved to your account.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                    ForEach(CoordinatedTheme.allCases) { theme in
                        paletteOption(theme)
                    }
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

                section("AI companion") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use the AI companion", isOn: Binding(get: { store.aiEnabled }, set: { store.setAIConsent($0) }))
                            .font(.system(size: 15))
                        Text("Powers chat, AI meal ideas and your daily plan using Google's Gemini through Firebase. When it's on, the data it needs (messages, cycle dates, recent logs and food preferences) is sent to answer you. Turning it off clears this session's AI results.")
                            .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                    }
                }

                section("Floating companion") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show floating robot", isOn: Binding(
                            get: { store.aiEnabled && floatingRobotEnabled },
                            set: { enabled in floatingRobotEnabled = store.aiEnabled && enabled }
                        ))
                        .font(.system(size: 15))
                        .disabled(!store.aiEnabled)

                        Button {
                            placement.isEditing = true
                            dismiss()
                        } label: {
                            Label("Edit position", systemImage: "hand.draw")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(minHeight: 38)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.aiEnabled || !floatingRobotEnabled)

                        Text(store.aiEnabled
                             ? "Tap the robot to open Companion. Use Edit position to drag it smoothly, then tap Done. It sleeps when idle."
                             : "Turn on the AI companion above before enabling the floating robot.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }

                section("Your data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your logs are stored in your private account and only you can read them. Nothing is sold, and nothing is sent to AI unless you turn the companion on.")
                            .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        outlineButton("Delete all my data") { confirmingDelete = true }
                        outlineButton("Delete account") {
                            deletePassword = ""
                            confirmingAccountDelete = true
                        }
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
            if usesPassword {
                SecureField("Password", text: $deletePassword)
            }
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount(store, password: usesPassword ? deletePassword : nil) }
            }
            .disabled(usesPassword && deletePassword.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(usesPassword
                 ? "This erases all your data and your sign-in. Enter your password to confirm. This can't be undone."
                 : "This erases all your data and your sign-in. Google users will be asked to confirm with Google. This can't be undone.")
        }
        .onAppear {
            auth.error = nil
            guard let p = store.profile else { return }
            name = p.name
            lastStart = store.periodHistory.records.map(\.start).max() ?? p.lastPeriodStart
            cycleLength = p.cycleLength
            periodLength = p.periodLength
            method = p.birthControl?.method
            packStart = p.birthControl?.packStart ?? .now
            activeDays = p.birthControl?.packStart == nil ? 21 : p.birthControl?.activeDays
        }
    }

    private func paletteOption(_ theme: CoordinatedTheme) -> some View {
        let selected = PalettePreferences.shared.theme == theme
        let colors = theme.colors
        return Button { store.setPalette(theme) } label: {
            HStack(spacing: 12) {
                HStack(spacing: -6) {
                    Circle().fill(Color(hex: colors.pastel))
                    Circle().fill(Color(hex: colors.secondaryPastel))
                }
                .frame(width: 50, height: 28)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.name).font(.subheadline.weight(.semibold))
                    Text(theme.detail).font(.caption).foregroundStyle(Palette.inkSoft)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color(hex: colors.accent) : Palette.inkSoft)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.ink)
            .padding(12)
            .frame(minHeight: 64)
            .background(selected ? Color(hex: colors.primarySurface) : Palette.surface,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color(hex: colors.secondaryPastel) : Palette.line, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityValue(theme.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Changes the app's full color palette")
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
