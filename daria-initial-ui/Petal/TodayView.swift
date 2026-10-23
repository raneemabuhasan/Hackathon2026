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
        Reminder.greeting(hour: Calendar.current.component(.hour, from: date))
    }

    // MARK: Cycle ring

    /// The date the ring is showing, so the button acts on that day.
    private var ringDate: Date {
        if let packDay = store.packDay {
            return CycleStore.add(store.today, (previewDay ?? packDay) - packDay)
        }
        return CycleStore.add(store.lastStart, (previewDay ?? max(1, store.cycleDay)) - 1)
    }

    private var hero: some View {
        let period = store.period(on: ringDate)
        return VStack(spacing: 26) {
            switch store.cycleMode {
            case .natural: CycleRing(previewDay: $previewDay)
            case .pack: PackRing(previewDay: $previewDay)
            case .steady: steadySummary
            }
            VStack(spacing: 16) {
                Button {
                    showPeriodEntry = true
                } label: {
                    Text("Period started")
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
            LinearGradient(colors: [Palette.blushPink, Palette.mist, Palette.cream],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .sheet(isPresented: $showPeriodEntry) {
            PeriodQuickEntry(period: period, date: min(ringDate, store.today)).environment(store)
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
        let daysTo = max(0, CycleStore.days(store.windowStart, from: store.today))
        // Old predictions may end in the past. Never divide by zero or give SwiftUI NaN frames.
        let total = Double(max(1, CycleStore.days(store.windowEnd, from: store.today) + 4))
        let pct = { (d: Date) in
            min(1.0, max(0.0, Double(CycleStore.days(d, from: store.today)) / total))
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: store.tracksPhases ? "Next period, likely" : "Next bleed, likely")
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

            if store.tracksPhases {
                Text(store.completedCycles.isEmpty
                     ? "Based on the \(store.average)-day cycle you told us. This gets more accurate as you log periods."
                     : "Based on your last \(store.pastLengths.count) cycles (\(store.pastLengths.min()!)–\(store.pastLengths.max()!) days). The window widens if your cycles vary more.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
                // From Raneem's version: be clear this is an estimate, and never for contraception.
                Text("This is an approximate window, not a guaranteed date. Calendar-only ovulation estimate: around cycle day \(max(1, store.average - 14)). Ovulation isn't confirmed; don't use this for contraception.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
            } else {
                Text("Based on your \(store.birthControl?.method.scheduleNoun ?? "pack") schedule. A bleed in the break is a withdrawal bleed, not a period, and it can be lighter, later or skipped.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
            }
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
            if !store.aiEnabled { AIOffNotice(feature: "a daily plan based on your logs") }
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
    private var actualDay: Int { max(1, store.cycleDay) }
    private var actualRingDay: Int { min(cycleLength, actualDay) }
    private var actualPhase: Phase { store.phase(forDay: actualRingDay) }

    // Keep the reference's rose tones in the default theme; other themes retain their palette.
    private func ringColor(_ phase: Phase) -> Color {
        guard PalettePreferences.shared.theme == .blush else { return phase.color }
        switch phase {
        case .menstrual: return Color(hex: 0xD50046)
        case .follicular: return Color(hex: 0xF5B2C7)
        case .ovulation: return Color(hex: 0xEF709D)
        case .luteal: return Color(hex: 0xB90040)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let radius = size / 2 - 16
                let angle = (Double(selectedDay) - 0.5) / Double(cycleLength) * 2 * .pi - .pi / 2

                let todayAngle = (Double(actualRingDay) - 0.5) / Double(cycleLength) * 2 * .pi - .pi / 2

                ZStack {
                    ForEach(Phase.allCases) { phase in
                        // A very short cycle can leave a phase with no days; skip its arc.
                        if let range = store.range(of: phase) {
                            Circle()
                                .trim(from: Double(range.lowerBound - 1) / Double(cycleLength) + 0.012,
                                      to: Double(range.upperBound) / Double(cycleLength) - 0.012)
                                .stroke(ringColor(phase), style: StrokeStyle(lineWidth: 17,
                                                                      lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(16)
                        }
                    }

                    VStack(spacing: 5) {
                        Text("CYCLE DAY")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2.2)
                            .foregroundStyle(Palette.inkSoft)
                        Text("\(shownDay)")
                            .font(.display(82)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("\(selectedPhase.name) phase")
                            .font(.display(24))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("of your \(cycleLength)-day cycle")
                            .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                    }
                    .padding(.horizontal, 36)
                    .allowsHitTesting(false)

                    if selectedDay != actualRingDay {
                        Circle()
                            .fill(Color(white: 0.88))
                            .overlay(Circle().stroke(Color.gray.opacity(0.55), lineWidth: 2.5))
                            .frame(width: 34, height: 34)
                            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                            .position(x: size / 2 + radius * cos(todayAngle),
                                      y: size / 2 + radius * sin(todayAngle))
                            .allowsHitTesting(false)
                    }

                    ZStack {
                        Circle().fill(.clear)
                        Circle()
                            .fill(.white)
                            .overlay(Circle().stroke(Palette.ink, lineWidth: 2.5))
                            .frame(width: 34, height: 34)
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
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cycle day preview")
            .accessibilityValue("Exploring day \(shownDay) of about \(cycleLength), \(selectedPhase.name) phase. Today is day \(actualDay), \(actualPhase.name) phase.")
            .accessibilityHint("Adjust to explore a day without changing your saved cycle")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: previewDay = min(cycleLength, selectedDay + 1)
                case .decrement: previewDay = max(1, selectedDay - 1)
                @unknown default: break
                }
            }

            ViewThatFits(in: .horizontal) {
                legend(spacing: 12)
                legend(spacing: 5)
            }

            Label("Drag the circle to explore your cycle", systemImage: "hand.draw")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
    }

    private func legend(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Phase.allCases) { phase in
                HStack(spacing: 4) {
                    Circle().fill(ringColor(phase)).frame(width: 7, height: 7)
                    Text(phase == .menstrual ? "Period" : phase == .ovulation ? "Mid-cycle" : phase.name)
                        .font(.system(size: 11, weight: phase == selectedPhase ? .bold : .regular))
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

/// Today's place in a 28-day pack, patch or ring cycle, with the break marked.
/// Like CycleRing, dragging only previews a day and never writes anything.
struct PackRing: View {
    @Environment(CycleStore.self) private var store
    @Binding var previewDay: Int?

    var body: some View {
        let length = BirthControl.packLength
        let active = store.birthControl?.activeDays ?? length
        let actualDay = min(length, max(1, store.packDay ?? 1))
        let day = previewDay ?? actualDay
        let todayAngle = (Double(actualDay) - 0.5) / Double(length) * 2 * .pi - .pi / 2
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
                    if day != actualDay {
                        Circle()
                            .fill(Color(white: 0.88))
                            .overlay(Circle().stroke(Color.gray.opacity(0.55), lineWidth: 2.5))
                            .frame(width: 28, height: 28)
                            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                            .position(x: size / 2 + radius * cos(todayAngle),
                                      y: size / 2 + radius * sin(todayAngle))
                            .allowsHitTesting(false)
                    }
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
            .accessibilityValue("Exploring day \(day) of \(length), \(day <= active ? "active days" : "break"). Today is day \(actualDay).")
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
    @State private var error: String?

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
            .disabled(store.periodStorageError != nil)

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
    }

    private func save() {
        do {
            if let period {
                try store.savePeriod(id: period.id, start: period.start, end: date)
            } else { try store.savePeriod(start: date, end: nil) }
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
