import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(CycleStore.self) private var store

    var body: some View {
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    DisplayTitle(before: "Hi Maya, ", accent: "be gentle", after: " today")
                }
                Spacer()
                Text("M")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 42, height: 42)
                    .background(Palette.accentSoft, in: Circle())
            }

            hero
            prediction
            week
            quickActions
            Text("The wellness plan below uses demo data.").font(.caption).foregroundStyle(Palette.inkSoft)
            plan
        }
    }

    // MARK: Cycle ring

    private var hero: some View {
        VStack(spacing: 12) {
            CycleRing()
                .frame(width: 230, height: 230)
            Text("Estimates adapt as you log your cycle")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            Button("Edit cycle details") { store.showCycleSetup = true }
                .font(.caption)

        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(colors: [Palette.blush, Palette.mist, Palette.cream],
                           center: .top, startRadius: 0, endRadius: 380),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    // MARK: Prediction

    private var prediction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Estimated next period")
            if let next = store.forecast.next() {
                Text("\(store.fmt(CycleStore.add(next, -store.forecast.margin))) – \(store.fmt(CycleStore.add(next, store.forecast.margin)))")
                    .font(.display(28))
                if next < store.today {
                    Text("The estimated date has passed. Log a period if it happened; dates are never filled in automatically.")
                        .font(.caption)
                }
            } else {
                Text("Log a start date to see an estimate.")
            }
            Text(store.forecastBasis).font(.caption)
            Text("This is an approximate window, not a guaranteed date.").font(.caption)
            Text("Typical bleeding length: \(store.baseline?.periodDays ?? 5) days. Your actual end date is always yours to record.").font(.caption)
            Text("Calendar-only ovulation estimate: around cycle day \(max(1, store.forecast.length - 14)). Ovulation is not confirmed; do not use this estimate for contraception.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
        }.card()
    }

    // MARK: Week strip

    private var week: some View {
        HStack(spacing: 6) {
            ForEach(-3...3, id: \.self) { offset in
                let d = CycleStore.add(store.today, offset)
                let period = store.periodHistory.contains(d)
                let predicted = store.forecast.next().map { next in
                    d >= CycleStore.add(next, -store.forecast.margin) && d <= CycleStore.add(next, store.forecast.margin)
                } ?? false
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
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your plan for today", trailing: "optional")
            ForEach(planItems, id: \.title) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 40, height: 40)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Text(item.detail).font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        if item.nhs {
                            Link("Source: NHS", destination: CycleStore.nhsPeriodPain)
                                .font(.system(size: 11)).foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
        }
        .card()
    }
}

@MainActor
struct CycleRing: View {
    @Environment(CycleStore.self) private var store
    @State private var showEntry = false

    private var countdown: String {
        guard let next = store.forecast.next() else { return "Next period: learning" }
        let days = CycleStore.days(next, from: store.today)
        if days < 0 { return "Estimated date passed" }
        if days == 0 { return "Estimated around today" }
        return "Next period in ~\(days) days"
    }
    var body: some View {
        ZStack {
            Circle().stroke(Palette.pink.opacity(0.35), lineWidth: 14).padding(10)
            Circle().trim(from: 0, to: progress)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(10)
            VStack(spacing: 10) {
                Text(countdown).font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                if let active = store.ongoingPeriod {
                    Text("Period day \(CycleStore.days(store.today, from: active.start) + 1)")
                        .font(.headline)
                }
                Button { showEntry = true } label: {
                    VStack(spacing: 3) {
                        Text(store.ongoingPeriod == nil ? "Period started" : "Period ended")
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                        Text("tap here").font(.caption)
                    }.foregroundStyle(Palette.ink).padding(.vertical, 8)
                }.buttonStyle(.plain)
            }.frame(maxWidth: 180)
        }
        .sheet(isPresented: $showEntry) { PeriodQuickEntry().environment(store) }
    }
    private var progress: Double {
        guard let start = store.forecast.start else { return 0 }
        return min(1, max(0, Double(CycleStore.days(store.today, from: start) + 1) / Double(store.forecast.length)))
    }
}

@MainActor
struct PeriodQuickEntry: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let active = store.ongoingPeriod { Text("Started \(store.fmt(active.start))") }
                DatePicker("Actual date", selection: $date, in: ...Date(), displayedComponents: .date)
                Text("Choose today or a previous date. Changes can also be corrected on the Cycle calendar.")
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save") {
                    do {
                        if let active = store.ongoingPeriod {
                            try store.savePeriod(id: active.id, start: active.start, end: date)
                        } else { try store.savePeriod(start: date, end: nil) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(store.periodStorageError != nil)
                if let error = store.periodStorageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(store.ongoingPeriod == nil ? "Period started" : "Period ended")
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
                    Stepper("\(periodDays) days", value: $periodDays, in: 1...90)
                    Text("Your usual number of bleeding days, not a limit on your records.").font(.caption)
                }
                Section("Typical cycle length") {
                    Toggle("I know my usual cycle length", isOn: $knowsCycle)
                    if knowsCycle { Stepper("\(cycleDays) days", value: $cycleDays, in: 2...365) }
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
