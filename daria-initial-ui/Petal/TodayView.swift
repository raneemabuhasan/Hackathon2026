import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @State private var showMood = false
    @State private var showSymptoms = false
    @State private var showFlow = false
    @State private var showSettings = false
    @State private var showPeriodEntry = false
    @State private var headerHeight: CGFloat = 0
    /// Day picked on the cycle ring; nil means today.
    @State private var previewDay: Int?
    @AppStorage("petal.planCompletions.v1") private var planCompletions = Data()

    @State private var editing: ReminderSheet?

    /// Which reminder the editor sheet is open for.
    private enum ReminderSheet: Identifiable {
        case new, edit(Reminder)
        var id: String { if case let .edit(r) = self { return r.id } else { return "new" } }
    }

    var body: some View {
        GeometryReader { viewport in
            Page {
                HStack(alignment: .top) {
                    // Re-checks every minute so the greeting moves on from morning to afternoon by itself.
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            DisplayTitle(
                                before: Self.greeting(at: context.date) + (store.name.isEmpty ? "" : ", "),
                                accent: store.name
                            )
                        }
                    }

                    Spacer()

                    Button { showSettings = true } label: {
                        Text(String(store.name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 42, height: 42)
                            .background(Palette.accentSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .background {
                    GeometryReader { header in
                        Color.clear.preference(key: TodayHeaderHeight.self, value: header.size.height)
                    }
                }

                hero(minHeight: max(0, viewport.size.height - headerHeight - 34))
                    .padding(.top, -10)
                week
                quickActions
                Text("The wellness plan below uses demo data.").font(.caption).foregroundStyle(Palette.inkSoft)
                plan
                reminders
            }
        }
        .sheet(isPresented: $showFlow) {
            LogSheet(flowOnly: true)
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
        .sheet(isPresented: $showSymptoms) {
            LogSheet(symptomsOnly: true)
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
        .sheet(isPresented: $showMood) {
            LogSheet(moodOnly: true)
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
        .onPreferenceChange(TodayHeaderHeight.self) { headerHeight = $0 }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(store)
                .environment(auth)
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(Palette.accent)
                    .frame(width: 40, height: 40)
                    .background(Palette.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reminders").font(.cardSubheading).foregroundStyle(Palette.wine)
                    Text("Little nudges for your routine")
                        .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            if let error = store.remindersError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !store.remindersLoaded {
                ProgressView("Loading reminders")
            } else if store.reminders.isEmpty {
                Text("Add a reminder for your daily routine or a day that works for you.")
                    .font(.system(size: 14)).foregroundStyle(Palette.inkSoft)
            }
            ForEach(store.reminders) { r in
                HStack(spacing: 12) {
                    Button { editing = .edit(r) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(r.title).font(.system(size: 14, weight: .semibold))
                                Text(r.detail(windowStart: store.windowStart)).font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit reminder")
                    Toggle(r.title, isOn: Binding(get: { r.on }, set: { store.setReminder(r, on: $0) }))
                        .labelsHidden()
                        .tint(Palette.accent)
                }
                .padding(12)
            }
            Button { editing = .new } label: {
                Text("New reminder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
        }
        .card()
        .sheet(item: $editing) { target in
            ReminderEditor(reminder: { if case let .edit(r) = target { return r } else { return nil } }())
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
    }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Cycle ring

    /// The date the ring is showing so the button acts on that day.
    private var ringDate: Date {
        if let packDay = store.packDay {
            return CycleStore.add(store.today, (previewDay ?? packDay) - packDay)
        }
        return CycleStore.add(store.lastStart, (previewDay ?? max(1, store.cycleDay)) - 1)
    }

    // MARK: Cycle ring

    private func hero(minHeight: CGFloat) -> some View {
        // A completed period can include today; only an unfinished record can be ended.
        let period = store.ongoingPeriod
        return VStack(spacing: 12) {
            switch store.cycleMode {
            case .natural: CycleRing(previewDay: $previewDay)
            case .pack: PackRing(previewDay: $previewDay)
            case .steady: steadySummary
            }
            VStack(spacing: 12) {
                Button {
                    showPeriodEntry = true
                } label: {
                    Text(period == nil ? (store.tracksPhases ? "Period started" : "Bleed started") : (store.tracksPhases ? "Period ended" : "Bleed ended"))
                }
                .buttonStyle(PeriodEntryPressStyle())

                Button("Edit cycle details") { store.showCycleSetup = true }
                    .font(.system(size: 13, weight: .medium))
                    .tint(Palette.wine)
                    .frame(minHeight: 44)
            }
            prediction
                .padding(.horizontal, -16)
                .padding(.bottom, -14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottom)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFAC8D4), Palette.mist, Palette.cream],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.wine.opacity(0.09), radius: 10, x: 0, y: 6)
        }
        .sheet(isPresented: $showPeriodEntry) {
            PeriodQuickEntry(period: period, date: store.today).environment(store)
        }
    }

    /// Hero for methods with no predictable bleed: just the method, and why there's no ring.
    private var steadySummary: some View {
        VStack(spacing: 10) {
            Eyebrow(text: "Birth control")
            Text(store.birthControl?.method.name ?? "")
                .font(.display(40))
            Text("Bleeding can be irregular or stop on this method, so Sync doesn't show phases or predict bleeds. Log any bleeding or spotting to see your own pattern.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    // MARK: Prediction

    @ViewBuilder
    private var prediction: some View {
        if store.predictsBleeds { predictionCard }
    }

    private var predictionCard: some View {
        let earliest = max(0, CycleStore.days(store.windowStart, from: store.today))
        let latest = max(0, CycleStore.days(store.windowEnd, from: store.today))
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                store.tab = .cycle
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Palette.rose)
                    Rectangle()
                        .fill(Palette.rose.opacity(0.25))
                        .frame(width: 1, height: 36)
                    VStack(alignment: .leading, spacing: 5) {
                        Text((store.tracksPhases ? "Next period, estimated" : "Next bleed, estimated").uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Palette.inkSoft)
                        Text("\(store.fmt(store.windowStart)) – \(store.fmt(store.windowEnd))")
                            .font(.display(19))
                            .foregroundStyle(Palette.wine)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Text("in \(earliest)–\(latest) days")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(EstimatePressStyle())
            .accessibilityHint("Opens the Calendar page. Dates are estimates.")

            if store.tracksPhases {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.activeAIForecast == nil ? "Based on your average cycle" : "✨ AI-adjusted")
                    if let forecast = store.activeAIForecast { Text(forecast.reason) }
                }
                .font(.caption).foregroundStyle(Palette.inkSoft)
                Text(store.completedCycles.isEmpty
                     ? "Based on the \(store.average)-day cycle you told us. This gets more accurate as you log periods."
                     : "Based on your last \(store.pastLengths.count) cycles (\(store.pastLengths.min()!)–\(store.pastLengths.max()!) days). The window widens if your cycles vary more.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
                Text("This is an approximate window, not a guaranteed date. Calendar-only ovulation estimate: around cycle day \(max(1, store.average - 14)). Ovulation isn't confirmed; don't use this for contraception.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
            } else {
                Text("Based on your \(store.birthControl?.method.scheduleNoun ?? "pack") schedule. A bleed in the break is a withdrawal bleed, not a period, and it can be lighter, later or skipped.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
            }
        }
    }

    // MARK: Week strip

    private var week: some View {
        HStack(spacing: 6) {
            ForEach(-3...3, id: \.self) { offset in
                let d = CycleStore.add(store.today, offset)
                let period = store.hasPeriod(on: d) || store.expectedPeriodStart(for: d) != nil
                let predicted = store.isPredicted(d) || store.isMaybe(d)
                VStack(spacing: 6) {
                    Text(d.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                    Text("\(CycleStore.cal.component(.day, from: d))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(period ? Color.white : Palette.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(period ? Palette.accent : predicted ? Color.clear : Palette.surface))
                        .overlay(Circle().strokeBorder(Palette.pink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).opacity(predicted ? 1 : 0))
                        .overlay(Circle().stroke(Palette.ink, lineWidth: 2).padding(-4).opacity(offset == 0 ? 1 : 0))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quick("Mood", "face.smiling")
            quick("Symptoms", "heart")
            quick("Flow", "drop")
        }
    }

    private func quick(_ title: String, _ icon: String) -> some View {
        Button {
            if title == "Mood" { showMood = true }
            else if title == "Symptoms" { showSymptoms = true }
            else if title == "Flow" { showFlow = true }
            else { store.showLog = true }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Palette.accent)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Palette.berry.opacity(0.07), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Plan

    private var completedPlanKeys: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: planCompletions)) ?? [])
    }

    /// Length-prefixed components keep task identities distinct across users, days and plans.
    private func planCompletionKey(icon: String, title: String, detail: String, isAI: Bool) -> String {
        let day = CycleStore.cal.dateComponents([.era, .year, .month, .day], from: store.today)
        let components = [store.uid, "\(day.era ?? 0)-\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)",
                          store.foodPhase.rawValue, isAI ? "ai" : "default", icon, title, detail]
        return components.map { "\($0.utf8.count):\($0)" }.joined()
    }

    private func togglePlanCompletion(_ key: String) {
        var keys = completedPlanKeys
        if !keys.insert(key).inserted { keys.remove(key) }
        if let data = try? JSONEncoder().encode(keys.sorted()) {
            planCompletions = data
        }
    }

    private var planItems: [(icon: String, title: String, detail: String, nhs: Bool)] {
        switch store.foodPhase {
        case .menstrual: [("leaf", "Warm lentil & spinach dal", "Iron-rich and easy on low-appetite days.", false),
                          ("drop", "Heat pad + water bottle", "Heat on your lower tummy is a common comfort.", true),
                          ("moon", "Early night", "Aim for a wind-down by 10 pm.", false)]
        case .follicular: [("leaf", "Chickpea quinoa salad", "Protein and fibre for busy days.", false),
                           ("figure.walk", "Try something new", "A class or a longer walk, if you feel like it.", false),
                           ("moon", "Evening check-in", "Two taps to log your mood.", false)]
        case .ovulation: [("leaf", "Rainbow grain bowl", "Lots of colour, tahini dressing.", false),
                    ("figure.walk", "30-minute walk", "Regular exercise can help with period pain over time.", true),
                    ("drop", "Refill your water", "You've logged high energy this week.", false)]
        case .luteal: [("leaf", "Sweet potato & bean chili", "Slow-release carbs for steadier energy.", false),
                       ("figure.yoga", "Gentle stretch", "10 minutes of yoga before bed.", false),
                       ("bag", "Pack your period kit", "Your period may start from \(store.fmt(store.windowStart)).", false)]
        }
    }

    private var plan: some View {
        let ai = store.plan
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Your plan for today").font(.cardSubheading)
                if ai != nil {
                    Text("AI").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.accentSoft, in: Capsule())
                }
                Spacer()
                if store.planLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(ai == nil ? "optional" : "from today's log").font(.caption).foregroundStyle(Palette.inkFaint)
                }
            }
            if !store.aiEnabled { AIOffNotice(feature: "a daily plan based on your logs") }
            ForEach(ai.map { $0.map { (icon: $0.icon, title: $0.title, detail: $0.detail, nhs: false) } } ?? planItems, id: \.title) { item in
                let key = planCompletionKey(icon: item.icon, title: item.title, detail: item.detail, isAI: ai != nil)
                let completed = completedPlanKeys.contains(key)
                HStack(alignment: .top, spacing: 14) {
                    Button { togglePlanCompletion(key) } label: {
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(completed ? Palette.accent : Palette.inkFaint)
                            .frame(width: 28, height: 22)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -11)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(completed ? "Completed" : "Not completed")
                    .accessibilityHint(completed ? "Mark as incomplete" : "Mark as complete")
                    Image(systemName: item.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 28, height: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Text(item.detail).font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        if item.nhs {
                            Link("Source: NHS", destination: CycleStore.nhsPeriodPain)
                                .font(.system(size: 11)).foregroundStyle(Palette.accent)
                        }
                    }
                    .opacity(completed ? 0.6 : 1)
                }
            }
            if ai != nil {
                Text("AI suggestions, not medical advice.").font(.caption).foregroundStyle(Palette.inkFaint)
            }
        }
        .card()
        .animation(.easeOut(duration: 0.25), value: ai)
        .task(id: store.planContext) { await store.loadPlan() }
    }
}

/// Explores the user's cycle day by day. Selection never writes to the recorded cycle.
struct CycleRing: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var previewDay: Int?

    /// Same length and phases as the prediction card, calendar and Nourish.
    private var cycleLength: Int { store.average }

    /// Today's day; can run past the usual length when a period is late.
    private var shownDay: Int { previewDay ?? max(1, store.cycleDay) }
    /// Where the handle sits, which stops at the end of the ring.
    private var selectedDay: Int { min(cycleLength, shownDay) }

    private var selectedPhase: Phase { store.phase(forDay: selectedDay) }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let radius = size / 2 - 16
                let angle = (Double(selectedDay) - 0.5) / Double(cycleLength) * 2 * .pi - .pi / 2

                ZStack {
                    ForEach(Phase.allCases) { phase in
                        // A very short cycle can leave a phase with no days; skip its arc.
                        if let range = store.range(of: phase) {
                            Circle()
                                .trim(from: Double(range.lowerBound - 1) / Double(cycleLength) + 0.012,
                                      to: Double(range.upperBound) / Double(cycleLength) - 0.012)
                                .stroke(phase.color, style: StrokeStyle(lineWidth: phase == selectedPhase ? 16 : 14,
                                                                      lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(16)
                        }
                    }

                    VStack(spacing: 4) {
                        Text("Cycle day".uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Palette.inkSoft)
                        Text("\(shownDay)")
                            .font(.display(74)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(selectedPhase == .menstrual ? "Menstrual phase" : "\(selectedPhase.name) phase")
                            .font(.display(19))
                            .foregroundStyle(Palette.wine)
                        Text("of your \(cycleLength)-day cycle")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .allowsHitTesting(false)

                    ZStack {
                        Circle().fill(.clear)
                        Circle()
                            .fill(.white)
                            .overlay(Circle().stroke(Palette.ink, lineWidth: 2.5))
                            .frame(width: 32, height: 32)
                            .shadow(color: Palette.wine.opacity(0.14), radius: 5, y: 2)
                    }
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("cyclePreviewRing"))
                        .onChanged { value in selectDay(at: value.location, size: size) })
                    .modifier(CycleHandlePosition(angle: angle, radius: radius, center: size / 2))
                }
                .frame(width: size, height: size)
                .coordinateSpace(name: "cyclePreviewRing")
            }
            .frame(width: 280, height: 280)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cycle day preview")
            .accessibilityValue("Day \(shownDay) of your \(cycleLength)-day cycle, \(selectedPhase.name) phase")
            .accessibilityHint("Adjust to explore a day without changing your saved cycle")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: previewDay = min(cycleLength, selectedDay + 1)
                case .decrement: previewDay = max(1, selectedDay - 1)
                @unknown default: break
                }
            }

            HStack(spacing: 0) {
                ForEach(Phase.allCases) { phase in
                    phaseLabel(phase)
                    if phase != Phase.allCases.last {
                        Spacer(minLength: 6)
                    }
                }
            }
            .frame(width: 280)

            ZStack {
                if previewDay != nil {
                    Button("Return to today") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                            previewDay = nil
                        }
                    }
                        .font(.system(size: 13, weight: .medium))
                        .tint(Palette.inkSoft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .transition(.opacity)
                } else {
                    Label("Drag the circle to explore your cycle", systemImage: "hand.draw")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkFaint)
                        .transition(.opacity)
                }
            }
            .frame(height: 44)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: previewDay != nil)
        }
    }

    private func phaseLabel(_ phase: Phase) -> some View {
        HStack(spacing: 4) {
            Circle().fill(phase.color).frame(width: 7, height: 7)
            Text(phase.name)
                .font(.system(size: 12, weight: phase == selectedPhase ? .bold : .regular))
                .fixedSize()
        }
        .foregroundStyle(phase == selectedPhase ? Palette.ink : Palette.inkSoft)
        .accessibilityAddTraits(phase == selectedPhase ? .isSelected : [])
    }

    private func selectDay(at point: CGPoint, size: CGFloat) {
        let x = point.x - size / 2
        let y = point.y - size / 2
        guard hypot(x, y) > 20 else { return }
        let fullTurn = 2 * Double.pi
        let angle = (atan2(Double(y), Double(x)) + Double.pi / 2 + fullTurn)
            .truncatingRemainder(dividingBy: fullTurn)
        previewDay = min(cycleLength, max(1, Int(angle / fullTurn * Double(cycleLength)) + 1))
    }
}

/// Interpolate the angle so the handle follows the ring instead of crossing its center.
private struct CycleHandlePosition: AnimatableModifier {
    var angle: Double
    let radius: CGFloat
    let center: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.position(x: center + radius * cos(angle),
                         y: center + radius * sin(angle))
    }
}

/// Today's place in a 28-day pack, patch or ring cycle, with the break marked.
/// Like CycleRing, dragging only previews a day and never writes anything.
struct PackRing: View {
    @Environment(CycleStore.self) private var store
    @Binding var previewDay: Int?

    var body: some View {
        let length = BirthControl.packLength
        let active = store.birthControl?.activeDays ?? length
        let day = previewDay ?? store.packDay ?? 1
        let angle = (Double(day) - 0.5) / Double(length) * 2 * .pi - .pi / 2
        VStack(spacing: 16) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let radius = size / 2 - 16
                ZStack {
                    arc(from: 0, to: active, length: length, color: Palette.blush, current: day <= active)
                    if active < length {
                        arc(from: active, to: length, length: length, color: Palette.rose, current: day > active)
                    }
                    VStack(spacing: 4) {
                        Eyebrow(text: store.birthControl?.method == .combinedPill ? "Pack day" : "Day")
                        Text("\(day)").font(.display(68)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of \(length)").font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                    }
                    .allowsHitTesting(false)
                    ZStack {
                        Circle().fill(.clear)
                        Circle()
                            .fill(.white)
                            .overlay(Circle().stroke(Palette.ink, lineWidth: 2.5))
                            .frame(width: 28, height: 28)
                            .shadow(color: Palette.wine.opacity(0.12), radius: 3, y: 2)
                    }
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("packPreviewRing"))
                        .onChanged { value in selectDay(at: value.location, size: size, length: length) })
                    .position(x: size / 2 + radius * cos(angle), y: size / 2 + radius * sin(angle))
                }
                .frame(width: size, height: size)
                .coordinateSpace(name: "packPreviewRing")
            }
            .frame(width: 230, height: 230)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pack day preview")
            .accessibilityValue("Day \(day) of \(length), \(day <= active ? "active days" : "break")")
            .accessibilityHint("Adjust to explore a day without changing anything")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: previewDay = min(length, day + 1)
                case .decrement: previewDay = max(1, day - 1)
                @unknown default: break
                }
            }

            HStack(spacing: 12) {
                legend(Palette.blush, "Active", bold: day <= active)
                legend(Palette.rose, "Break", bold: day > active)
            }

            if previewDay != nil {
                Button("Preview · Back to today") { previewDay = nil }
                    .font(.system(size: 11, weight: .medium))
                    .tint(Palette.inkSoft)
            }
        }
    }

    private func selectDay(at point: CGPoint, size: CGFloat, length: Int) {
        let x = point.x - size / 2
        let y = point.y - size / 2
        guard hypot(x, y) > 20 else { return }
        let fullTurn = 2 * Double.pi
        let angle = (atan2(Double(y), Double(x)) + Double.pi / 2 + fullTurn)
            .truncatingRemainder(dividingBy: fullTurn)
        let picked = min(length, max(1, Int(angle / fullTurn * Double(length)) + 1))
        previewDay = picked == store.packDay ? nil : picked
    }

    private func arc(from start: Int, to end: Int, length: Int, color: Color, current: Bool) -> some View {
        Circle()
            .trim(from: Double(start) / Double(length) + 0.012, to: Double(end) / Double(length) - 0.012)
            .stroke(color, style: StrokeStyle(lineWidth: current ? 16 : 14, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(16)
    }

    private func legend(_ color: Color, _ label: String, bold: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: bold ? .bold : .regular))
        }
        .foregroundStyle(bold ? Palette.ink : Palette.inkSoft)
    }
}

@MainActor
struct PeriodQuickEntry: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The period being ended, or nil to start a new one.
    let period: PeriodRecord?
    @State var date: Date
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var error: String?

    private var laterPeriod: PeriodRecord? {
        store.periodHistory.records
            .filter { CycleStore.cal.startOfDay(for: $0.start) > CycleStore.cal.startOfDay(for: date) }
            .min { $0.start < $1.start }
    }

    private var needsEndDate: Bool { period == nil && laterPeriod != nil }

    /// An end can't come before its start.
    private var earliest: Date { period.map { CycleStore.cal.startOfDay(for: $0.start) } ?? .distantPast }

    /// One-tap answers for the usual case: today or the two days before.
    private var recentDays: [Date] {
        (0..<3).map { CycleStore.add(store.today, -$0) }.filter { $0 >= earliest }
    }

    private func label(_ day: Date) -> String {
        if CycleStore.cal.isDateInToday(day) { return "Today" }
        if CycleStore.cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(eyebrow: period.map { "Period · day \(CycleStore.days(store.today, from: $0.start) + 1)" } ?? "Period") {
                dismiss()
            } title: {
                DisplayTitle(before: "When did it ", accent: period == nil ? "start?" : "end?", size: 30)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(recentDays, id: \.self) { day in
                        Chip(label: label(day), selected: CycleStore.cal.isDate(day, inSameDayAs: date)) { date = day }
                    }
                }
                Divider()
                DatePicker("Another day", selection: $date, in: earliest...Date(), displayedComponents: .date)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSoft)
                if period == nil {
                    Toggle("This period has ended", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ended", selection: $endDate, in: date...Date.now, displayedComponents: .date)
                    }
                    if needsEndDate, let laterPeriod {
                        Text("You have a later period starting \(store.fmt(laterPeriod.start)). Enter the end date for this earlier period so it isn't saved as still ongoing.")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                if let period {
                    Text("Started \(store.fmt(period.start)).").font(.caption).foregroundStyle(Palette.inkFaint)
                }
            }
            .card()

            if let error = error ?? store.periodStorageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button(action: save) {
                Text(period == nil ? "Start period on \(store.fmt(date))" : "End period on \(store.fmt(date))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.periodStorageError != nil || (needsEndDate && !hasEndDate))

            Text("You can fix dates anytime on the Cycle calendar.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .fittedSheet()
        .onChange(of: date) { _, newDate in
            if endDate < newDate { endDate = newDate }
            error = nil
        }
        .onChange(of: endDate) { _, _ in error = nil }
        .onChange(of: hasEndDate) { _, _ in error = nil }
    }

    private func save() {
        do {
            if let period {
                try store.savePeriod(id: period.id, start: period.start, end: date)
            } else { try store.savePeriod(start: date, end: hasEndDate ? endDate : nil) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct CycleSetupView: View {
    @Environment(CycleStore.self) private var store
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var knowsStart = true
    @State private var periodDays = 5
    @State private var cycleDays = 28
    @State private var knowsCycle = false
    @State private var error: String?
    /// What the sheet opened with, so Save only lights up after an edit.
    @State private var original: CycleBaseline?

    /// The answers as they'd be saved. Fields behind an "I don't know" toggle don't count.
    private var edited: CycleBaseline {
        CycleBaseline(lastStart: knowsStart ? CycleStore.cal.startOfDay(for: start) : nil,
                      periodDays: periodDays, cycleDays: knowsCycle ? cycleDays : nil)
    }
    private var changed: Bool { edited != original }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(eyebrow: "Cycle details") {
                store.showCycleSetup = false
            } title: {
                DisplayTitle(before: "Your cycle ", accent: "basics", size: 30)
            }

            section("Most recent period", note: "Used as a baseline for estimates. We never infer an actual end date.") {
                Toggle("I know the start date", isOn: $knowsStart)
                if knowsStart {
                    Divider().overlay(Palette.line)
                    DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: .date)
                }
            }

            section("Typical bleeding length", note: "Your usual number of bleeding days, not a limit on your records.") {
                stepper("Bleeding days", value: $periodDays, range: 2...10)
            }

            section("Typical cycle length", note: "Count from the first day of one period to the first day of the next. If unsure, we begin with a 28-day estimate.") {
                Toggle("I know my usual cycle length", isOn: $knowsCycle)
                if knowsCycle {
                    Divider().overlay(Palette.line)
                    stepper("Cycle length", value: $cycleDays, range: 18...45)
                }
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            Button {
                do {
                    try store.saveBaseline(edited, ongoing: false)
                } catch { self.error = error.localizedDescription }
            } label: {
                // Say why it's disabled instead of just fading out, like Settings.
                Text(changed ? "Save changes" : "No changes to save")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Palette.accent.opacity(changed ? 1 : 0.4), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!changed)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .animation(.easeOut(duration: 0.2), value: knowsStart)
        .animation(.easeOut(duration: 0.2), value: knowsCycle)
        .fittedSheet()
        .onAppear {
            let saved = store.baseline
            start = saved?.lastStart ?? store.periodHistory.records.first?.start ?? store.today
            knowsStart = saved == nil || saved?.lastStart != nil
            periodDays = saved?.periodDays ?? 5
            cycleDays = saved?.cycleDays ?? 28
            knowsCycle = saved?.cycleDays != nil
            original = edited
        }
    }

    private func section<C: View>(_ title: String, note: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            VStack(spacing: 12) { content() }
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSoft)
            Text(note).font(.caption).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
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
}

private struct EstimatePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 1.025 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PeriodEntryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? Palette.rose : Color.white)
            .padding(.horizontal, 34)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? Color.white : Palette.accent, in: Capsule())
            .overlay {
                Capsule().strokeBorder(configuration.isPressed ? Palette.rose : .clear, lineWidth: 1.5)
            }
            .shadow(color: Palette.wine.opacity(0.14), radius: 5, y: 3)
    }
}

private struct TodayHeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
