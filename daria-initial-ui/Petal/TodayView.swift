import SwiftUI

struct TodayView: View {
    @Environment(CycleStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @State private var showSettings = false

    var body: some View {
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    DisplayTitle(before: "Hi \(store.name), ", accent: "be gentle", after: " today")
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

    // MARK: Cycle ring

    private var hero: some View {
        VStack(spacing: 12) {
            CycleRing()
                .frame(width: 230, height: 230)
            HStack(spacing: 6) {
                Circle().fill(store.currentPhase.color).frame(width: 8, height: 8)
                Text("\(store.currentPhase.name) phase").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.surface.opacity(0.75), in: Capsule())
            HStack(spacing: 14) {
                ForEach(Phase.allCases) { p in
                    HStack(spacing: 5) {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                        Text(p.name).font(.system(size: 11))
                    }
                }
            }
            .foregroundStyle(Palette.ink.opacity(0.85))
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
        }
        .card()
    }

    // MARK: Week strip

    private var week: some View {
        HStack(spacing: 6) {
            ForEach(-3...3, id: \.self) { offset in
                let d = CycleStore.add(store.today, offset)
                let period = store.isPeriod(d), predicted = store.isPredicted(d)
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

struct CycleRing: View {
    @Environment(CycleStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let inset: CGFloat = 10
            let radius = size / 2 - inset
            let avg = Double(store.average)
            let gap = 0.018

            ZStack {
                Circle().stroke(Palette.ink.opacity(0.07), lineWidth: 16).padding(inset)
                ForEach(Phase.allCases) { phase in
                    let r = store.range(of: phase)
                    Circle()
                        .trim(from: Double(r.lowerBound - 1) / avg + gap, to: Double(r.upperBound) / avg - gap)
                        .stroke(phase.color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                }
                let angle = (Double(store.cycleDay) - 0.5) / avg * 2 * .pi - .pi / 2
                Circle()
                    .fill(Palette.surface)
                    .overlay(Circle().stroke(Palette.ink, lineWidth: 3))
                    .frame(width: 26, height: 26)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))

                VStack(spacing: 2) {
                    Eyebrow(text: "Cycle day")
                    Text("\(store.cycleDay)").font(.display(68)).monospacedDigit()
                    Text("of about \(store.average) days").font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                }
            }
            .frame(width: size, height: size)
        }
    }
}
