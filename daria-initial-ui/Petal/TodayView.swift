import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @State private var showSettings = false
    @State private var showPeriodEntry = false
    /// Day picked on the cycle ring; nil means today.
    @State private var previewDay: Int?

    var body: some View {
        Page {
            HStack(alignment: .top) {
                // Re-checks every minute so the greeting moves on from morning to afternoon by itself.
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        DisplayTitle(before: Self.greeting(at: context.date) + (store.name.isEmpty ? "" : ", "),
                                     accent: store.name)
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

            hero
            prediction
            week
            quickActions
            Text("The wellness plan below uses demo data.").font(.caption).foregroundStyle(Palette.inkSoft)
            plan
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(store)
                .environment(auth)
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

    /// The date the ring is showing, so the button acts on that day.
    private var ringDate: Date {
        CycleStore.add(store.lastStart, (previewDay ?? max(1, store.cycleDay)) - 1)
    }

    private var hero: some View {
        let period = store.period(on: ringDate)
        return VStack(spacing: 26) {
            CycleRing(previewDay: $previewDay)
            VStack(spacing: 16) {
                Button {
                    showPeriodEntry = true
                } label: {
                    Text(period == nil ? "Period started" : "Period ended")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button("Edit cycle details") { store.showCycleSetup = true }
                    .font(.system(size: 11, weight: .medium))
                    .tint(Palette.inkSoft)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0xF7BAC9), Palette.mist, Palette.cream],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .sheet(isPresented: $showPeriodEntry) {
            PeriodQuickEntry(period: period, date: min(ringDate, store.today)).environment(store)
        }
    }

    // MARK: Prediction

       private var prediction: some View {
        let daysTo = max(0, CycleStore.days(store.windowStart, from: store.today))
        let total = Double(CycleStore.days(store.windowEnd, from: store.today) + 4)
        let pct = { (d: Date) in Double(CycleStore.days(d, from: store.today)) / total }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "Next period, likely")
                Spacer()
                Text("in \(daysTo)–\(daysTo + store.spread * 2) days").font(.caption).foregroundStyle(Palette.inkFaint)
            }
            Text("\(store.fmt(store.windowStart)) – \(store.fmt(store.windowEnd))")
                .font(.display(30))
                .monospacedDigit()

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface2).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.blush.opacity(0), Palette.pink, Palette.blush.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * (pct(store.windowEnd) - pct(store.windowStart) + 0.08), height: 14)
                        .offset(x: w * (pct(store.windowStart) - 0.04))
                    RoundedRectangle(cornerRadius: 2).fill(Palette.ink).frame(width: 3, height: 22)
                }
                .frame(height: 24)
            }
            .frame(height: 24)
            HStack {
                Text("Today")
                Spacer()
                Text(store.fmt(CycleStore.add(store.today, Int(total))))
            }
            .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)

            Text(store.completedCycles.isEmpty
                 ? "Based on the \(store.average)-day cycle you told us. This gets more accurate as you log periods."
                 : "Based on your last \(store.pastLengths.count) cycles (\(store.pastLengths.min()!)–\(store.pastLengths.max()!) days). The window widens if your cycles vary more.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
            // From Raneem's version: be clear this is an estimate, and never for contraception.
            Text("This is an approximate window, not a guaranteed date. Calendar-only ovulation estimate: around cycle day \(max(1, store.average - 14)). Ovulation isn't confirmed; don't use this for contraception.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
        }
        .card()
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
        Button { store.showLog = true } label: {
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

    private var planItems: [(icon: String, title: String, detail: String, nhs: Bool)] {
        switch store.currentPhase {
        case .menstrual: [("leaf", "Warm lentil & spinach dal", "Iron-rich and easy on low-appetite days.", false),
                          ("drop", "Heat pad + water bottle", "Heat on your lower tummy is a common comfort.", true),
                          ("moon", "Early night", "Aim for a wind-down by 10 pm.", false)]
        case .follicular: [("leaf", "Chickpea quinoa salad", "Protein and fibre for busy days.", false),
                           ("figure.walk", "Try something new", "A class or a longer walk, if you feel like it.", false),
                           ("moon", "Evening check-in", "Two taps to log your mood.", false)]
        case .mid: [("leaf", "Rainbow grain bowl", "Lots of colour, tahini dressing.", false),
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
                Text("Your plan for today").font(.system(size: 15, weight: .semibold))
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
            ForEach(ai.map { $0.map { (icon: $0.icon, title: $0.title, detail: $0.detail, nhs: false) } } ?? planItems, id: \.title) { item in
                HStack(alignment: .top, spacing: 14) {
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
    @Binding var previewDay: Int?

    /// Same length and phases as the prediction card, calendar and Nourish.
    private var cycleLength: Int { store.average }

    /// Today's day; can run past the usual length when a period is late.
    private var shownDay: Int { previewDay ?? max(1, store.cycleDay) }
    /// Where the handle sits, which stops at the end of the ring.
    private var selectedDay: Int { min(cycleLength, shownDay) }

    private var selectedPhase: Phase { store.phase(forDay: selectedDay) }

    var body: some View {
        VStack(spacing: 16) {
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
                        Eyebrow(text: "Cycle day")
                        Text("\(shownDay)")
                            .font(.display(68)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of about \(cycleLength) days")
                            .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
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
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("cyclePreviewRing"))
                        .onChanged { value in selectDay(at: value.location, size: size) })
                    .position(x: size / 2 + radius * cos(angle),
                              y: size / 2 + radius * sin(angle))
                }
                .frame(width: size, height: size)
                .coordinateSpace(name: "cyclePreviewRing")
            }
            .frame(width: 230, height: 230)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cycle day preview")
            .accessibilityValue("Day \(shownDay) of about \(cycleLength), \(selectedPhase.name) phase")
            .accessibilityHint("Adjust to explore a day without changing your saved cycle")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: previewDay = min(cycleLength, selectedDay + 1)
                case .decrement: previewDay = max(1, selectedDay - 1)
                @unknown default: break
                }
            }

            HStack(spacing: 6) {
                Circle().fill(selectedPhase.color).frame(width: 8, height: 8)
                Text("\(selectedPhase.name) phase")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.surface.opacity(0.8), in: Capsule())

            ViewThatFits(in: .horizontal) {
                legend(spacing: 12)
                legend(spacing: 5)
            }

            if previewDay != nil {
                Button("Preview · Back to today") { previewDay = nil }
                    .font(.system(size: 11, weight: .medium))
                    .tint(Palette.inkSoft)
            }
        }
    }

    private func legend(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Phase.allCases) { phase in
                HStack(spacing: 4) {
                    Circle().fill(phase.color).frame(width: 6, height: 6)
                    Text(phase.name)
                        .font(.system(size: 10, weight: phase == selectedPhase ? .bold : .regular))
                }
                .foregroundStyle(phase == selectedPhase ? Palette.ink : Palette.inkSoft)
            }
        }
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

@MainActor
struct PeriodQuickEntry: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The period being ended, or nil to start a new one.
    let period: PeriodRecord?
    @State var date: Date
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let period { Text("Started \(store.fmt(period.start))") }
                DatePicker("Actual date", selection: $date, in: ...Date(), displayedComponents: .date)
                Text("Choose today or a previous date. Changes can also be corrected on the Cycle calendar.")
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save") {
                    do {
                        if let period {
                            try store.savePeriod(id: period.id, start: period.start, end: date)
                        } else { try store.savePeriod(start: date, end: nil) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(store.periodStorageError != nil)
                if let error = store.periodStorageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(period == nil ? "Period started" : "Period ended")
            .toolbar { Button("Cancel") { dismiss() } }
        }
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
    @State private var ongoing = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Most recent period") {
                    Toggle("I know the start date", isOn: $knowsStart)
                    if knowsStart {
                        DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: .date)
                        if store.ongoingPeriod == nil { Toggle("This period is still ongoing", isOn: $ongoing) }
                    }
                    Text("Used as a baseline for estimates. We never infer an actual end date.").font(.caption)
                }
                Section("Typical bleeding length") {
                    Stepper("\(periodDays) days", value: $periodDays, in: 2...10)
                    Text("Your usual number of bleeding days, not a limit on your records.").font(.caption)
                }
                Section("Typical cycle length") {
                    Toggle("I know my usual cycle length", isOn: $knowsCycle)
                    if knowsCycle { Stepper("\(cycleDays) days", value: $cycleDays, in: 18...45) }
                    Text("Count from the first day of one period to the first day of the next. If unsure, we begin with a 28-day estimate.").font(.caption)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save and continue") {
                    do {
                        try store.saveBaseline(CycleBaseline(lastStart: knowsStart ? start : nil,
                            periodDays: periodDays, cycleDays: knowsCycle ? cycleDays : nil), ongoing: knowsStart && ongoing)
                    } catch { self.error = error.localizedDescription }
                }
            }
            .navigationTitle("Your cycle basics")
            .toolbar {
                if store.baseline != nil { Button("Cancel") { store.showCycleSetup = false } }
            }
            .onAppear {
                let saved = store.baseline
                start = saved?.lastStart ?? store.periodHistory.records.first?.start ?? store.today
                knowsStart = saved == nil || saved?.lastStart != nil
                periodDays = saved?.periodDays ?? 5
                cycleDays = saved?.cycleDays ?? 28
                knowsCycle = saved?.cycleDays != nil
            }
        }.interactiveDismissDisabled()
    }
}
