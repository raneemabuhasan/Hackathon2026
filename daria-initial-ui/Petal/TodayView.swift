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
    @State private var heroRingHeight: CGFloat = 0
    @State private var heroLowerHeight: CGFloat = 0
    /// Day picked on the cycle ring; nil means today.
    @State private var previewDay: Int?
    @AppStorage("petal.planCompletions.v1") private var planCompletions = Data()

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
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
        .onChange(of: store.average) { _, _ in previewDay = nil }
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

    private func hero(minHeight: CGFloat) -> some View {
        // A completed period can include today; only an unfinished record can be ended.
        let period = store.ongoingPeriod
        // Spare height (e.g. no prediction card on some birth control) is split above and below the ring,
        // so it sits centered instead of leaving a gap at the top. Parts are measured without the spacers.
        let slack = max(0, minHeight - 28 - 12 - heroRingHeight - heroLowerHeight)
        return VStack(spacing: 12) {
            Group {
                switch store.cycleMode {
                case .natural: CycleRing(previewDay: $previewDay)
                case .pack: PackRing(previewDay: $previewDay)
                case .steady: SteadySummary()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroRingHeight = $0 }
            .padding(.top, slack / 2)
            .padding(.bottom, slack / 2)
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    Button {
                        showPeriodEntry = true
                    } label: {
                        Text(period == nil ? (store.tracksPhases ? "Period started" : "Bleed started") : (store.tracksPhases ? "Period ended" : "Bleed ended"))
                    }
                    .buttonStyle(PeriodEntryPressStyle())

                    Button(store.tracksPhases ? "Edit cycle details" : "Edit bleeding details") { store.showCycleSetup = true }
                        .font(.system(size: 13, weight: .medium))
                        .tint(Palette.wine)
                        .frame(minHeight: 44)
                }
                prediction
                    .padding(.horizontal, -16)
                    .padding(.bottom, -14)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroLowerHeight = $0 }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottom)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Palette.blushPink, Palette.mist, Palette.cream],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.wine.opacity(0.09), radius: 10, x: 0, y: 6)
        }
        .sheet(isPresented: $showPeriodEntry) {
            PeriodQuickEntry(period: period, date: store.today).environment(store)
        }
    }

    // MARK: Prediction

    @ViewBuilder
    private var prediction: some View {
        if store.predictsBleeds { predictionCard }
    }

    /// One line on how the window was worked out, so the estimate never looks like a promise.
    private var predictionBasis: String {
        if !store.tracksPhases { return "Based on your \(store.birthControl?.method.scheduleNoun ?? "pack") schedule" }
        if let forecast = store.activeAIForecast { return "✨ AI-adjusted · \(forecast.reason)" }
        if store.completedCycles.isEmpty { return "Based on the \(store.average)-day cycle you told us" }
        let lengths = store.pastLengths
        return "Based on your last \(lengths.count) cycle\(lengths.count == 1 ? "" : "s") (\(lengths.min() ?? store.average)–\(lengths.max() ?? store.average) days)"
    }

    private var predictionCard: some View {
        let earliest = max(0, CycleStore.days(store.windowStart, from: store.today))
        let latest = max(0, CycleStore.days(store.windowEnd, from: store.today))
        return Button {
            store.tab = .cycle
        } label: {
            VStack(alignment: .leading, spacing: 10) {
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
                Text(predictionBasis)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(EstimatePressStyle())
        .accessibilityHint("Opens the Calendar page. Dates are estimates.")
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
    @State private var showsPhaseExplanation = false

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

    private var phaseExplanation: String {
        switch selectedPhase {
        case .menstrual:
            "During menstruation, the uterus sheds its lining. Rest and gentle movement may feel supportive."
        case .follicular:
            "During the follicular phase, follicles develop in the ovaries and the uterine lining begins to build again."
        case .ovulation:
            "Ovulation is when an ovary releases an egg. This calendar estimate cannot confirm when ovulation happens."
        case .luteal:
            "After ovulation, the uterine lining prepares for a possible pregnancy. Some people notice PMS symptoms before their period."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
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
                                .stroke(phase.color, style: StrokeStyle(lineWidth: phase == selectedPhase ? 16 : 14,
                                                                      lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(16)
                        }
                    }

                    ZStack {
                        if showsPhaseExplanation {
                            VStack(spacing: 14) {
                                Text("\(selectedPhase.name.uppercased()) PHASE")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Palette.inkSoft)
                                PhaseRingIcon(phase: selectedPhase)
                                    .frame(width: 36, height: 36)
                                Text(phaseExplanation)
                                    .font(.system(size: 13))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .transition(.push(from: .trailing))
                        } else {
                            VStack(spacing: 5) {
                                Text("CYCLE DAY")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(2.2)
                                    .foregroundStyle(Palette.inkSoft)
                                Text("\(shownDay)")
                                    .font(.display(74)).monospacedDigit()
                                    .contentTransition(.numericText())
                                Text("of your \(cycleLength)-day cycle")
                                    .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                            }
                            .transition(.push(from: .leading))
                        }
                    }
                    .frame(width: max(0, size - 88), height: max(0, size - 88))
                    // Keep the sliding pages inside the ring.
                    .clipped()
                    .contentShape(Circle())
                    .onTapGesture { showPage(explanation: !showsPhaseExplanation) }
                    .gesture(DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height),
                                  abs(value.translation.width) > 30 else { return }
                            // Like any pager: swipe left for the next page, right to go back.
                            showPage(explanation: value.translation.width < 0)
                        })
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 0) {
                            pageDot(explanation: false)
                            pageDot(explanation: true)
                        }
                        .offset(y: 16)
                        .accessibilityHidden(true)
                    }

                    if selectedDay != actualRingDay {
                        Circle()
                            .fill(Color(white: 0.88))
                            .overlay(Circle().stroke(Color.gray.opacity(0.55), lineWidth: 2.5))
                            .frame(width: 32, height: 32)
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
            .accessibilityValue("Exploring day \(shownDay) of about \(cycleLength), \(selectedPhase.name) phase. Today is day \(actualDay), \(actualPhase.name) phase.")
            .accessibilityHint("Adjust to explore a day without changing your saved cycle")
            .accessibilityAction(named: showsPhaseExplanation ? "Show cycle day" : "Show phase explanation") {
                showsPhaseExplanation.toggle()
            }
            .accessibilityCustomContent("Phase explanation", showsPhaseExplanation ? phaseExplanation : "Swipe left or tap inside the circle to read about this phase")
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
            PhaseRingIcon(phase: phase).frame(width: 14, height: 14)
            Text(phase.name)
                .font(.system(size: 12, weight: phase == selectedPhase ? .bold : .regular))
                .fixedSize()
        }
        .foregroundStyle(phase == selectedPhase ? Palette.ink : Palette.inkSoft)
        .accessibilityAddTraits(phase == selectedPhase ? .isSelected : [])
    }

    private func showPage(explanation: Bool) {
        guard explanation != showsPhaseExplanation else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            showsPhaseExplanation = explanation
        }
    }

    /// A page indicator dot that also jumps to its page when tapped.
    private func pageDot(explanation: Bool) -> some View {
        let current = explanation == showsPhaseExplanation
        return Button { showPage(explanation: explanation) } label: {
            Circle()
                .fill(current ? Palette.ink : Palette.ink.opacity(0.2))
                .frame(width: 7, height: 7)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Reference-matched vector artwork; backgrounds and the flower's center are transparent.
struct PhaseRingIcon: View {
    let phase: Phase

    /// Same color as the phase's arc on the ring, so the icons follow the chosen theme.
    private var colors: [Color] { [phase.color, phase.color.opacity(0.88)] }

    var body: some View {
        ZStack {
            PhaseIconSilhouette(phase: phase)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                      style: FillStyle(eoFill: phase == .ovulation))
            if phase == .follicular {
                // Normalized geometry keeps the seed proportional at ring and legend sizes.
                PhaseIconDetail(phase: phase).fill(Palette.rose)
            } else if phase == .menstrual || phase == .luteal {
                PhaseIconDetail(phase: phase)
                    .fill(phase == .menstrual ? Palette.petal : Palette.blushPink)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Unit-coordinate paths keep each silhouette reusable at any display resolution.
struct PhaseIconSilhouette: Shape {
    let phase: Phase

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch phase {
        case .menstrual:
            p.move(to: CGPoint(x: 0.48, y: 0.025))
            p.addQuadCurve(to: CGPoint(x: 0.52, y: 0.025), control: CGPoint(x: 0.5, y: -0.005))
            p.addCurve(to: CGPoint(x: 0.88, y: 0.61), control1: CGPoint(x: 0.63, y: 0.19), control2: CGPoint(x: 0.86, y: 0.46))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.99), control1: CGPoint(x: 0.99, y: 0.88), control2: CGPoint(x: 0.77, y: 0.99))
            p.addCurve(to: CGPoint(x: 0.12, y: 0.61), control1: CGPoint(x: 0.23, y: 0.99), control2: CGPoint(x: 0.01, y: 0.88))
            p.addCurve(to: CGPoint(x: 0.48, y: 0.025), control1: CGPoint(x: 0.14, y: 0.46), control2: CGPoint(x: 0.37, y: 0.19))
            p.closeSubpath()
        case .follicular:
            var left = Path()
            left.move(to: CGPoint(x: 0.33, y: 0.025))
            left.addCurve(to: CGPoint(x: 0.47, y: 0.98), control1: CGPoint(x: -0.21, y: 0.38), control2: CGPoint(x: -0.01, y: 0.91))
            left.addQuadCurve(to: CGPoint(x: 0.46, y: 0.91), control: CGPoint(x: 0.5, y: 0.99))
            left.addCurve(to: CGPoint(x: 0.37, y: 0.08), control1: CGPoint(x: 0.18, y: 0.56), control2: CGPoint(x: 0.19, y: 0.37))
            left.addQuadCurve(to: CGPoint(x: 0.33, y: 0.025), control: CGPoint(x: 0.4, y: 0.015))
            left.closeSubpath()
            p.addPath(left)
            p.addPath(left, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0))
        case .ovulation:
            // Smooth five-lobed flower with a genuine transparent center.
            for step in 0...240 {
                let angle = Double(step) / 240 * 2 * .pi - .pi / 2
                let radius = 0.405 + 0.085 * cos(5 * (angle + .pi / 2))
                let point = CGPoint(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle))
                if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 0.385, y: 0.385, width: 0.23, height: 0.23))
        case .luteal:
            // Rounded plum with the shallow upper-right bite from the reference.
            p.move(to: CGPoint(x: 0.65, y: 0.045))
            p.addCurve(to: CGPoint(x: 0.89, y: 0.245), control1: CGPoint(x: 0.68, y: 0.16), control2: CGPoint(x: 0.8, y: 0.23))
            p.addCurve(to: CGPoint(x: 0.99, y: 0.56), control1: CGPoint(x: 0.97, y: 0.34), control2: CGPoint(x: 0.99, y: 0.43))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.99), control1: CGPoint(x: 0.99, y: 0.82), control2: CGPoint(x: 0.78, y: 0.99))
            p.addCurve(to: CGPoint(x: 0.01, y: 0.52), control1: CGPoint(x: 0.22, y: 0.99), control2: CGPoint(x: 0.01, y: 0.8))
            p.addCurve(to: CGPoint(x: 0.65, y: 0.045), control1: CGPoint(x: 0.01, y: 0.19), control2: CGPoint(x: 0.34, y: -0.055))
            p.closeSubpath()
        }
        if phase == .menstrual {
            p = p.applying(CGAffineTransform(a: 0.78, b: 0, c: 0, d: 1, tx: 0.11, ty: 0))
        }
        return fitted(p, in: rect)
    }
}

struct PhaseIconDetail: Shape {
    let phase: Phase

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch phase {
        case .menstrual:
            p.move(to: CGPoint(x: 0.75, y: 0.58))
            p.addCurve(to: CGPoint(x: 0.57, y: 0.86), control1: CGPoint(x: 0.82, y: 0.69), control2: CGPoint(x: 0.7, y: 0.84))
            p.addQuadCurve(to: CGPoint(x: 0.59, y: 0.81), control: CGPoint(x: 0.53, y: 0.85))
            p.addCurve(to: CGPoint(x: 0.71, y: 0.59), control1: CGPoint(x: 0.71, y: 0.74), control2: CGPoint(x: 0.71, y: 0.68))
            p.addQuadCurve(to: CGPoint(x: 0.75, y: 0.58), control: CGPoint(x: 0.71, y: 0.54))
            p.closeSubpath()
        case .follicular:
            p.addEllipse(in: CGRect(x: 0.32, y: 0.32, width: 0.36, height: 0.36))
        case .luteal:
            p.move(to: CGPoint(x: 0.65, y: 0.045))
            p.addCurve(to: CGPoint(x: 0.89, y: 0.245), control1: CGPoint(x: 0.68, y: 0.16), control2: CGPoint(x: 0.8, y: 0.23))
            p.addCurve(to: CGPoint(x: 0.67, y: 0.31), control1: CGPoint(x: 0.83, y: 0.32), control2: CGPoint(x: 0.75, y: 0.33))
            p.addCurve(to: CGPoint(x: 0.65, y: 0.045), control1: CGPoint(x: 0.59, y: 0.29), control2: CGPoint(x: 0.58, y: 0.17))
            p.closeSubpath()
        case .ovulation: break
        }
        if phase == .menstrual {
            p = p.applying(CGAffineTransform(a: 0.78, b: 0, c: 0, d: 1, tx: 0.11, ty: 0))
        }
        return fitted(p, in: rect)
    }
}

private func fitted(_ path: Path, in rect: CGRect) -> Path {
    let side = min(rect.width, rect.height)
    return path.applying(CGAffineTransform(a: side, b: 0, c: 0, d: side,
                                         tx: rect.midX - side / 2, ty: rect.midY - side / 2))
}


/// For methods without a schedule (mini-pill, shot, implant, hormonal IUD): no phases or predictions,
/// so the ring shows the user's own logged bleeding instead. Same footprint as CycleRing.
struct SteadySummary: View {
    @Environment(CycleStore.self) private var store

    private var today: Date { store.today }
    private var lastBleed: PeriodRecord? { store.bleedRecords.first { $0.start <= today } }
    private var bleedsLast90Days: Int {
        store.bleedRecords.filter { $0.start > CycleStore.add(today, -90) && $0.start <= today }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Palette.blush, lineWidth: 14)
                    .padding(16)
                VStack(spacing: 5) {
                    if let bleed = lastBleed, bleed.end == nil {
                        Eyebrow(text: "Bleed day")
                        Text("\(CycleStore.days(today, from: bleed.start) + 1)")
                            .font(.display(74)).monospacedDigit()
                        Text("since \(bleed.start.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                    } else if let bleed = lastBleed {
                        Eyebrow(text: "Days since bleeding")
                        Text("\(CycleStore.days(today, from: bleed.end ?? bleed.start))")
                            .font(.display(74)).monospacedDigit()
                        Text("on your \(store.birthControl?.method.name.lowercased() ?? "method")")
                            .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                    } else {
                        Eyebrow(text: "Birth control")
                        Text(store.birthControl?.method.name ?? "")
                            .font(.display(34))
                            .multilineTextAlignment(.center)
                        Text("No bleeding logged yet")
                            .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                    }
                }
                .padding(.horizontal, 44)
            }
            .frame(width: 280, height: 280)
            .accessibilityElement(children: .combine)

            HStack(spacing: 16) {
                stat(lastBleed.map { $0.start.formatted(.dateTime.month(.abbreviated).day()) } ?? "None", "last bleed")
                stat("\(bleedsLast90Days)", "bleeds in 90 days")
            }

            Text("Bleeding can be irregular or stop on this method, so Sync doesn't predict it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 12, weight: .bold))
            Text(label).font(.system(size: 12))
        }
        .foregroundStyle(Palette.ink)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var previewDay: Int?

    var body: some View {
        let length = BirthControl.packLength
        let active = store.birthControl?.activeDays ?? length
        let actualDay = min(length, max(1, store.packDay ?? 1))
        let day = previewDay ?? actualDay
        let todayAngle = (Double(actualDay) - 0.5) / Double(length) * 2 * .pi - .pi / 2
        let angle = (Double(day) - 0.5) / Double(length) * 2 * .pi - .pi / 2
        // Same sizes and spacing as CycleRing, so switching methods or previewing never moves the card.
        VStack(spacing: 12) {
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
                        Text("\(day)").font(.display(74)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of \(length)").font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                    }
                    .allowsHitTesting(false)
                    if day != actualDay {
                        Circle()
                            .fill(Color(white: 0.88))
                            .overlay(Circle().stroke(Color.gray.opacity(0.55), lineWidth: 2.5))
                            .frame(width: 32, height: 32)
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
                            .frame(width: 32, height: 32)
                            .shadow(color: Palette.wine.opacity(0.14), radius: 5, y: 2)
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
            .frame(width: 280, height: 280)
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

            HStack(spacing: 16) {
                legend(Palette.blush, "Active", bold: day <= active)
                if active < length {
                    legend(Palette.rose, "Break", bold: day > active)
                }
            }

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
                    Label("Drag the circle to explore your \(store.birthControl?.method.scheduleNoun.replacingOccurrences(of: "first ", with: "") ?? "pack")", systemImage: "hand.draw")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkFaint)
                        .transition(.opacity)
                }
            }
            .frame(height: 44)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: previewDay != nil)
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
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12, weight: bold ? .bold : .regular))
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
            SheetHeader(eyebrow: store.tracksPhases ? "Cycle details" : "Bleeding details") {
                store.showCycleSetup = false
            } title: {
                DisplayTitle(before: store.tracksPhases ? "Your cycle " : "Your bleeding ", accent: "basics", size: 30)
            }

            section("Most recent \(store.bleedName)", note: "Used as a baseline for estimates. We never infer an actual end date.") {
                Toggle("I know the start date", isOn: $knowsStart)
                if knowsStart {
                    Divider().overlay(Palette.line)
                    DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: .date)
                }
            }

            section("Typical bleeding length", note: "Your usual number of bleeding days, not a limit on your records.") {
                stepper("Bleeding days", value: $periodDays, range: 2...10)
            }

            // On hormonal birth control there's no cycle to measure; the pack schedule lives in Settings.
            if store.tracksPhases {
                section("Typical cycle length", note: "Count from the first day of one period to the first day of the next. If unsure, we begin with a 28-day estimate.") {
                    Toggle("I know my usual cycle length", isOn: $knowsCycle)
                    if knowsCycle {
                        Divider().overlay(Palette.line)
                        stepper("Cycle length", value: $cycleDays, range: 18...45)
                    }
                }
            } else if store.cycleMode == .pack {
                Text("Your \(store.birthControl?.method.scheduleNoun ?? "pack") start date and break are in Settings → Birth control.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
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
