import SwiftUI

/// Personal settings, opened from the gear in the top corner of Today.
/// A compact list of rows; each opens its own page.
struct SettingsView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private enum Page: Hashable {
        case profile, cycle, birthControl, reminders, appearance, companion, privacy
    }

    /// Which reminder the editor sheet is open for.
    private enum ReminderSheet: Identifiable {
        case new, edit(Reminder)
        var id: String { if case let .edit(r) = self { return r.id } else { return "new" } }
    }

    @State private var path: [Page] = []
    @State private var editingReminder: ReminderSheet?
    @State private var name = ""
    @State private var lastStart = Date.now
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var method: BirthControl.Method?
    @State private var packStart = Date.now
    @State private var activeDays: Int? = 21
    @State private var confirmingDelete = false
    @State private var confirmingAccountDelete = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var deletePassword = ""
    @State private var confirmingSignOut = false


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
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings").font(.display(34))
                        if let email = auth.user?.email {
                            Text(email).font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        }
                    }

                    group("General") {
                        link(.profile, value: trimmedName)
                        link(.cycle, value: "\(cycleLength) days")
                        link(.birthControl, value: method?.name ?? "None")
                        link(.reminders, value: "\(store.reminders.filter(\.on).count) on")
                        link(.appearance, value: PalettePreferences.shared.theme.name)
                        link(.companion, value: store.aiEnabled ? "On" : "Off")
                    }

                    group("Account") {
                        if usesPassword, let email = auth.user?.email {
                            row("Change password", icon: "key") {
                                Task { await auth.resetPassword(email: email) }
                            }
                        }
                        link(.privacy)
                    }
                    if let message = auth.error {
                        Text(message).font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                    }

                    Button { confirmingSignOut = true } label: {
                        Text("Sign out")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(Capsule().stroke(Palette.ink, lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Palette.bg)
            // Keep the bar on every page so it doesn't pop in and shift content after a push.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: Page.self) { page in
                Form {
                    header(for: page)
                    content(for: page)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Palette.bg)
                .navigationTitle(title(for: page))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if savesWithButton(page) {
                        ToolbarItem(placement: .confirmationAction) { saveButton }
                    }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .sheet(item: $editingReminder) { target in
            ReminderEditor(reminder: { if case let .edit(r) = target { return r } else { return nil } }())
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
        // Leaving a page without saving drops its edits.
        .onChange(of: path) { _, new in
            if new.isEmpty { load() }
        }
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
            load()
        }
    }

    private func load() {
        saveError = nil
        guard let p = store.profile else { return }
        name = p.name
        lastStart = store.periodHistory.records.map(\.start).max() ?? p.lastPeriodStart
        cycleLength = p.cycleLength
        periodLength = p.periodLength
        method = p.birthControl?.method
        packStart = p.birthControl?.packStart ?? .now
        activeDays = p.birthControl?.packStart == nil ? 21 : p.birthControl?.activeDays
    }

    private func title(for page: Page) -> String {
        switch page {
        case .profile: "Profile"
        case .cycle: "Your cycle"
        case .birthControl: "Birth control"
        case .reminders: "Reminders"
        case .appearance: "Appearance"
        case .companion: "AI companion"
        case .privacy: "Your data & privacy"
        }
    }

    private func icon(for page: Page) -> String {
        switch page {
        case .profile: "person"
        case .cycle: "calendar"
        case .birthControl: "pills"
        case .reminders: "bell"
        case .appearance: "paintpalette"
        case .companion: "sparkles"
        case .privacy: "lock.shield"
        }
    }

    private func blurb(for page: Page) -> String {
        switch page {
        case .profile: "What should we call you?"
        case .cycle: "Sync uses these to predict your period and phases."
        case .birthControl: "So predictions fit the method you use."
        case .reminders: "Reminders for your routine."
        case .appearance: "Pick the colors you'd like to see."
        case .companion: "Chat, meal ideas and a daily plan."
        case .privacy: "Your logs stay in your private account."
        }
    }

    /// Pages whose edits are kept until Save; the rest apply as soon as you tap.
    private func savesWithButton(_ page: Page) -> Bool {
        [.profile, .cycle, .birthControl].contains(page)
    }

    /// The icon and one-line summary at the top of each page.
    private func header(for page: Page) -> some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: icon(for: page))
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 56, height: 56)
                    .background(Palette.accentSoft, in: Circle())
                Text(blurb(for: page))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page {
        case .profile:
            Section {
                LabeledContent("First name") {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                        .multilineTextAlignment(.trailing)
                }
            }

        case .cycle:
            Section {
                DatePicker("Last period started", selection: $lastStart, in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                stepper("Usual cycle length", value: $cycleLength, range: 18...45)
                stepper("Usual period length", value: $periodLength, range: 2...10)
            } footer: {
                Text("Dates are estimates. Logging your periods makes them more accurate.")
            }

        case .birthControl:
            Section {
                Picker("Method", selection: Binding(get: { method }, set: { picked in
                    method = picked
                    if let picked, !picked.hasSchedule || (picked != .combinedPill && activeDays == 24) { activeDays = 21 }
                })) {
                    Text("None").tag(BirthControl.Method?.none)
                    ForEach(BirthControl.Method.allCases) { Text($0.name).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                if let method, method.hasSchedule {
                    DatePicker("Current \(method.scheduleNoun) started", selection: $packStart,
                               in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                    Picker("Breaks", selection: $activeDays) {
                        ForEach(birthControl?.regimens ?? [], id: \.label) { Text($0.label).tag($0.days) }
                    }
                    .pickerStyle(.menu)
                }
            } footer: {
                Text("Hormonal methods usually pause ovulation, so Sync hides cycle phases and predicts bleeds from your schedule, or not at all. Pill and patch reminders are under Reminders.")
            }

        case .reminders:
            Section {
                if let error = store.remindersError {
                    Text(error).foregroundStyle(Palette.wine)
                } else if !store.remindersLoaded {
                    ProgressView("Loading reminders")
                }
                ForEach(store.reminders) { reminder in
                    HStack(spacing: 12) {
                        Button { editingReminder = .edit(reminder) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.listName)
                                    .font(.system(size: 15))
                                    .lineLimit(1)
                                Text(reminder.detail(windowStart: store.windowStart))
                                    .font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit reminder")
                        Toggle(reminder.listName, isOn: Binding(
                            get: { reminder.on }, set: { store.setReminder(reminder, on: $0) }))
                            .labelsHidden()
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    // Our own background keeps the row square while it's swiped, instead of the system's rounded one.
                    .listRowBackground(Rectangle().fill(Palette.surface))
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { store.deleteReminder(reminder) }
                    }
                }
                Button { editingReminder = .new } label: {
                    Label("Add a reminder", systemImage: "plus")
                        .font(.system(size: 15))
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } footer: {
                Text("Tap a reminder to edit it, or swipe left to delete.")
            }

        case .appearance:
            Section {
                ForEach(CoordinatedTheme.allCases) { theme in
                    paletteOption(theme)
                }
            } footer: {
                Text("Text, backgrounds and accents change together. Saved to your account.")
            }

        case .companion:
            Section {
                Toggle("Use the AI companion", isOn: Binding(get: { store.aiEnabled }, set: { store.setAIConsent($0) }))
                Toggle("Use AI for period predictions", isOn: Binding(get: { store.aiPredictionsEnabled }, set: { store.setAIPredictions($0) }))
                    .disabled(!store.aiEnabled)
            } footer: {
                Text("Powers chat, AI meal ideas, your daily plan and optional period predictions using Google's Gemini through Firebase. When it's on, the data it needs (messages, cycle dates, recent logs and food preferences) is sent to answer you. Turning it off clears this session's AI results. Sync's average-based prediction is used offline, when predictions are off, and until you've logged 3 cycles.")
            }

        case .privacy:
            Section {
                Button("Delete all my data", role: .destructive) { confirmingDelete = true }
                Button("Delete account", role: .destructive) {
                    deletePassword = ""
                    confirmingAccountDelete = true
                }
            } footer: {
                Text(auth.error ?? "Your logs are stored in your private account and only you can read them. Nothing is sold, and nothing is sent to AI unless you turn the companion on.")
            }
        }

        if let saveError, savesWithButton(page) {
            Section {
                Text(saveError).foregroundStyle(Palette.wine)
            }
        }
    }

    /// Saves the profile, cycle and birth control together, then returns to the list.
    private var saveButton: some View {
        Button {
            saving = true
            saveError = nil
            Task {
                defer { saving = false }
                do {
                    try await store.updateProfile(name: trimmedName, lastPeriodStart: lastStart,
                                                  cycleLength: cycleLength, periodLength: periodLength)
                    if birthControl != store.profile?.birthControl { store.saveBirthControl(birthControl) }
                    path.removeAll()
                } catch {
                    saveError = error.localizedDescription
                }
            }
        } label: {
            if saving {
                ProgressView()
            } else {
                Text("Save").fontWeight(.semibold)
            }
        }
        .disabled(saving || !changed || trimmedName.isEmpty)
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
                .frame(width: 40, height: 22)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                    Text(theme.detail).font(.caption).foregroundStyle(Palette.inkFaint)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Palette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityValue(theme.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Changes the app's full color palette")
    }

    /// A titled run of rows, as in the General and Account groups.
    private func group<C: View>(_ title: String, @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 15, weight: .semibold))
                .padding(.bottom, 4)
            rows()
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) days").foregroundStyle(Palette.inkSoft).monospacedDigit()
            }
        }
    }

    private func link(_ page: Page, value: String = "") -> some View {
        row(title(for: page), icon: icon(for: page), value: value) { path.append(page) }
    }

    private func row(_ title: String, icon: String, value: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Palette.ink).frame(width: 24)
                Text(title).font(.system(size: 15))
                Spacer()
                if !value.isEmpty {
                    Text(value).font(.system(size: 14)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }
}
