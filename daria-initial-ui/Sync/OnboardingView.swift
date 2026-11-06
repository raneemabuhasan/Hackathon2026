import SwiftUI
import Lottie

/// First-run slides: cycle basics, reminders, food, then the AI companion. Nothing is saved until the last one.
struct OnboardingView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @State private var step = Step.cycle
    @State private var name = ""
    @State private var lastStart = CycleStore.add(.now, -10)
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var periodDaysBefore = 2
    @State private var logTime = CycleStore.cal.date(bySettingHour: 20, minute: 30, second: 0, of: .now) ?? .now
    @State private var diets: Set<String> = []
    @State private var avoid: Set<String> = []
    @State private var dislikes: [String] = []
    @State private var method: BirthControl.Method?
    @State private var packStart = CycleStore.add(.now, -7)
    @State private var activeDays: Int? = 21
    @State private var pillTime = CycleStore.cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var changeWeeks = 1
    @FocusState private var nameFocused: Bool

    private enum Step: Int, CaseIterable {
        case cycle, reminders, food, companion
    }


    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// What the rest of onboarding is based on, from the birth-control answer.
    private var birthControl: BirthControl? {
        method.map { m in
            m.hasSchedule ? BirthControl(method: m, packStart: CycleStore.cal.startOfDay(for: packStart), activeDays: activeDays)
                          : BirthControl(method: m)
        }
    }
    private var mode: CycleMode { birthControl?.mode ?? .natural }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case .cycle: cycleSlide
                    case .reminders: remindersSlide
                    case .food: foodSlide
                    case .companion: companionSlide
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .background(Palette.mist.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            // New accounts start on the default colors; completeOnboarding then saves this choice to the profile.
            PalettePreferences.shared.theme = .blush
            if name.isEmpty, let full = auth.user?.displayName {
                name = full.components(separatedBy: " ").first ?? full
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Palette.surface.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(step == .cycle ? 0 : 1)
            .disabled(step == .cycle)
            .accessibilityLabel("Back")

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Palette.ink : Palette.ink.opacity(0.15))
                        .frame(height: 3)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch step {
            case .cycle:
                primaryButton("Continue", enabled: !trimmedName.isEmpty) { go(1) }
                HStack(spacing: 4) {
                    Text("Not you?").foregroundStyle(Palette.inkSoft)
                    Button("Sign out") { auth.signOut() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.accent)
                }
                .font(.system(size: 14))
            case .reminders:
                primaryButton("Continue") {
                    // Asked here, right after they've chosen what they'll be reminded about.
                    ReminderNotifications.requestPermission()
                    go(1)
                }
            case .food:
                primaryButton(diets.isEmpty && avoid.isEmpty && dislikes.isEmpty ? "Skip for now" : "Continue") { go(1) }
            case .companion:
                primaryButton("Turn on companion") { finish(aiConsent: true) }
                Button("Not now") { finish(aiConsent: false) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Palette.accent.opacity(enabled ? 1 : 0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func go(_ delta: Int) {
        nameFocused = false
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func finish(aiConsent: Bool) {
        let log = CycleStore.cal.dateComponents([.hour, .minute], from: logTime)
        let pill = CycleStore.cal.dateComponents([.hour, .minute], from: pillTime)
        var reminders: [Reminder] = []
        if let method, method.isPill {
            reminders.append(Reminder(title: "Time for your pill", kind: .daily, hour: pill.hour ?? 9, minute: pill.minute ?? 0))
        } else if let method, method == .patch || method == .ring {
            reminders.append(Reminder(title: method == .patch ? "Time to change your patch" : "Time for your ring change",
                                      kind: .everyWeeks, hour: pill.hour ?? 9, minute: pill.minute ?? 0,
                                      date: CycleStore.add(CycleStore.cal.startOfDay(for: packStart), changeWeeks * 7), weeks: changeWeeks))
        }
        // On a pack, the last bleed is the latest break that has started; it seeds the period history.
        var lastBleed = lastStart
        if mode == .pack, let active = activeDays {
            lastBleed = CycleStore.add(packStart, active)
            while lastBleed > .now { lastBleed = CycleStore.add(lastBleed, -BirthControl.packLength) }
        }
        store.completeOnboarding(name: trimmedName, lastPeriodStart: lastBleed,
                                 cycleLength: mode == .pack ? BirthControl.packLength : cycleLength, periodLength: periodLength,
                                 logHour: log.hour ?? 20, logMinute: log.minute ?? 30,
                                 periodDaysBefore: periodDaysBefore,
                                 diets: diets, avoid: avoid, dislikes: dislikes, aiConsent: aiConsent,
                                 birthControl: birthControl, birthControlReminders: reminders)
    }

    // MARK: Slides

    private func heading(_ before: String, _ accent: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DisplayTitle(before: before, accent: accent, size: 36)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.system(size: 15)).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cycleSlide: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Tell us about ", "your cycle", "Rough answers are fine. Sync gets more accurate as you log.")
            OnboardingArt(animation: "heart", speed: 0.5)
            VStack(spacing: 0) {
                row {
                    TextField("Your first name", text: $name)
                        .textContentType(.givenName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                }
                Divider()
                row { birthControlPicker }
                if let method, method.hasSchedule {
                    Divider()
                    row {
                        DatePicker("\(method.scheduleNoun.prefix(1).uppercased() + method.scheduleNoun.dropFirst()) started",
                                   selection: $packStart, in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                    }
                    Divider()
                    row {
                        LabeledContent("Breaks") {
                            Picker("Breaks", selection: $activeDays) {
                                ForEach(birthControl?.regimens ?? [], id: \.label) { Text($0.label).tag($0.days) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                }
                if mode != .pack {
                    Divider()
                    row {
                        DatePicker(mode == .natural ? "Last period started" : "Last bleed started", selection: $lastStart,
                                   in: CycleStore.add(.now, -90)...Date.now, displayedComponents: .date)
                    }
                }
                if mode == .natural {
                    Divider()
                    row { stepper("Cycle length", value: $cycleLength, range: 18...45) }
                }
                if mode != .steady {
                    Divider()
                    row { stepper(mode == .natural ? "Period length" : "Period length", value: $periodLength, range: 2...10) }
                }
            }
            .background(Palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: method)

            if mode != .natural {
                Text("Hormonal birth control usually pauses ovulation, so Sync won't show cycle phases. You can change this in Settings.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var birthControlPicker: some View {
        LabeledContent("Birth control") {
            Picker("Birth control", selection: Binding(get: { method }, set: { picked in
                method = picked
                // Patches are usually changed weekly; rings stay in for three weeks.
                changeWeeks = picked == .ring ? 3 : 1
                if let picked, !picked.hasSchedule || (picked != .combinedPill && activeDays == 24) { activeDays = 21 }
            })) {
                Text("No").tag(BirthControl.Method?.none)
                ForEach(BirthControl.Method.allCases) { Text($0.name).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var remindersSlide: some View {
        let hour = CycleStore.cal.component(.hour, from: logTime)
        let greeting = Reminder.greeting(hour: hour) + (trimmedName.isEmpty ? "" : ", \(trimmedName)")
        return VStack(alignment: .leading, spacing: 18) {
            heading("A gentle ", "nudge", "Here's what Sync will send you. Change or turn these off anytime.")
            OnboardingArt(animation: "bell", height: 120)

            if let method, method.isPill {
                reminderPreview(when: pillTime.formatted(date: .omitted, time: .shortened), title: nil, message: "Time for your pill") {
                    DatePicker("Remind me at", selection: $pillTime, displayedComponents: .hourAndMinute)
                }
            } else if let method, method == .patch || method == .ring {
                let first = CycleStore.add(packStart, changeWeeks * 7)
                reminderPreview(when: first.formatted(.dateTime.month(.abbreviated).day()), title: nil,
                                message: method == .patch ? "Time to change your patch" : "Time for your ring change") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("How often")
                            Spacer()
                            roundButton("minus", label: "Less often") { changeWeeks = max(1, changeWeeks - 1) }
                                .disabled(changeWeeks == 1)
                            Text(changeWeeks == 1 ? "Weekly" : "\(changeWeeks) weeks")
                                .fontWeight(.semibold).monospacedDigit()
                                .frame(minWidth: 70)
                            roundButton("plus", label: "More weeks apart") { changeWeeks = min(4, changeWeeks + 1) }
                                .disabled(changeWeeks == 4)
                        }
                        .frame(minHeight: 54)
                        Divider()
                        DatePicker("Remind me at", selection: $pillTime, displayedComponents: .hourAndMinute)
                            .frame(minHeight: 54)
                    }
                }
            }

            if mode != .steady {
                let noun = mode == .natural ? "period" : "next bleed"
                reminderPreview(when: "\(periodDaysBefore) day\(periodDaysBefore == 1 ? "" : "s") before",
                                title: mode == .natural ? "Period may start soon" : "Bleed may start soon",
                                message: "Your \(noun) may start in about \(periodDaysBefore) day\(periodDaysBefore == 1 ? "" : "s").") {
                    Text("Heads-up")
                    Spacer()
                    roundButton("minus", label: "Fewer days") { periodDaysBefore = max(1, periodDaysBefore - 1) }
                        .disabled(periodDaysBefore == 1)
                    Text("\(periodDaysBefore) day\(periodDaysBefore == 1 ? "" : "s")")
                        .fontWeight(.semibold).monospacedDigit()
                        .frame(minWidth: 58)
                    roundButton("plus", label: "More days") { periodDaysBefore = min(7, periodDaysBefore + 1) }
                        .disabled(periodDaysBefore == 7)
                }
            }

            reminderPreview(when: logTime.formatted(date: .omitted, time: .shortened),
                            title: nil,
                            message: "\(greeting). Don't forget to log your symptoms today!") {
                DatePicker("Remind me at", selection: $logTime, displayedComponents: .hourAndMinute)
            }
        }
    }

    /// A mock lock-screen notification with the setting that shapes it underneath.
    private func reminderPreview<Control: View>(when: String, title: String?, message: String,
                                                @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Sync").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(when).font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
                    }
                    if let title { Text(title).font(.system(size: 14, weight: .semibold)) }
                    Text(message).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview: \(title.map { $0 + ". " } ?? "")\(message)")

            Divider().padding(.horizontal, 14)

            HStack(spacing: 10) { control() }
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
        }
        .background(Palette.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.berry.opacity(0.08), radius: 12, y: 4)
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.mist, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var foodSlide: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Any food ", "preferences?")
            OnboardingArt(animation: "cooking")
            FoodPreferencesForm(diets: $diets, avoid: $avoid, dislikes: $dislikes)
        }
    }

    private var companionSlide: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Meet your ", "companion", "Ask about your cycle, get meal ideas and a daily plan, or log how you feel just by chatting.")
            OnboardingArt(animation: "signin", loops: true)
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "How it works")
                bullet("sparkles", "The companion, AI meal ideas and your daily plan use Google's Gemini AI through Firebase.")
                bullet("arrow.up.doc", "To answer you, Sync sends your messages with your cycle dates, recent logs and food preferences.")
                bullet("hand.raised", "It's general wellness info, not medical advice.")
                bullet("slider.horizontal.3", "Everything else works without it, and you can switch it on or off in Settings.")
            }
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) days").fontWeight(.semibold).monospacedDigit()
            }
        }
    }
}

/// The illustration on each slide. Plays once and holds its final frame unless `loops` is set;
/// holds a still frame when Reduce Motion is on.
private struct OnboardingArt: View {
    let animation: String
    var height: CGFloat = 170
    var speed: Double = 1
    var loops = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LottieView(animation: .named(animation))
            .playbackMode(reduceMotion ? .paused(at: .progress(0.5)) : .playing(.toProgress(1, loopMode: loops ? .loop : .playOnce)))
            .configure { $0.animationSpeed = speed }
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}
