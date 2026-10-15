import SwiftUI

struct CycleView: View {
    @Environment(CycleStore.self) private var store
    @State private var monthOffset = 0

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Your cycle")
                DisplayTitle(before: "Patterns, ", accent: "not", after: " promises")
            }
            calendar
            lengths
            symptoms
        }
    }

    // MARK: Calendar

    private var month: Date {
        let comps = CycleStore.cal.dateComponents([.year, .month], from: store.today)
        let first = CycleStore.cal.date(from: comps)!
        return CycleStore.cal.date(byAdding: .month, value: monthOffset, to: first)!
    }

    private var calendar: some View {
        let cal = CycleStore.cal
        let lead = (cal.component(.weekday, from: month) + 5) % 7 // Monday-first
        let first = CycleStore.add(month, -lead)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(spacing: 14) {
            HStack {
                circleButton("chevron.left") { monthOffset -= 1 }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 15, weight: .semibold))
                Spacer()
                circleButton("chevron.right") { monthOffset += 1 }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                }
                ForEach(0..<42, id: \.self) { i in
                    dayCell(CycleStore.add(first, i))
                }
            }
            HStack(spacing: 14) {
                legend(Circle().fill(Palette.accent), "Logged period")
                legend(Circle().strokeBorder(Palette.pink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])), "Likely period")
                legend(Circle().fill(Palette.blush.opacity(0.4)), "Could start")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.inkSoft)
        }
        .card()
    }

    private func dayCell(_ d: Date) -> some View {
        let inMonth = CycleStore.cal.isDate(d, equalTo: month, toGranularity: .month)
        let period = store.isPeriod(d), predicted = store.isPredicted(d), maybe = store.isMaybe(d)
        let isToday = CycleStore.cal.isDate(d, inSameDayAs: store.today)
        return Text("\(CycleStore.cal.component(.day, from: d))")
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(period ? Color.white : Palette.ink)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(Circle().fill(period ? Palette.accent : maybe ? Palette.blush.opacity(0.4) : Color.clear))
            .overlay(Circle().strokeBorder(Palette.pink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).opacity(predicted ? 1 : 0))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2).opacity(isToday ? 1 : 0))
            .opacity(inMonth ? 1 : 0.35)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(Palette.line))
        }
        .buttonStyle(.plain)
    }

    private func legend(_ swatch: some View, _ text: String) -> some View {
        HStack(spacing: 6) { swatch.frame(width: 12, height: 12); Text(text) }
    }

    // MARK: Cycle lengths

    private var lengths: some View {
        let cycles = Array(store.completedCycles.reversed())
        let height = { (v: Int) in CGFloat(max(v - 16, 4)) / 18 * 90 }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cycle length", trailing: cycles.isEmpty ? nil : "last \(cycles.count) cycles")
            if cycles.isEmpty {
                Text("Log your next period and your cycle lengths will show up here.")
                    .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(cycles.enumerated()), id: \.offset) { _, c in
                        bar(value: c.length, height: height(c.length), label: c.start.formatted(.dateTime.month(.abbreviated)), highlight: false)
                    }
                    bar(value: store.average, height: height(store.average), label: "Avg", highlight: true)
                }
                .frame(height: 130, alignment: .bottom)
                Text("Your cycles vary by about \(store.pastLengths.max()! - store.pastLengths.min()!) days, which is common. If they start varying by more than 7–9 days, it may be worth mentioning to a doctor.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
            }
        }
        .card()
    }

    private func bar(value: Int, height: CGFloat, label: String, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 8)
                .fill(highlight ? Palette.accent : Palette.blush)
                .frame(maxWidth: 30)
                .frame(height: height)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Symptoms

    private var symptoms: some View {
        let counts = store.symptomCounts
        let top = Double(counts.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Symptom summary", trailing: "last 60 days")
            if counts.isEmpty {
                Text("No symptoms logged yet. Tap + to add today.")
                    .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            ForEach(counts, id: \.name) { item in
                HStack(spacing: 10) {
                    Text(item.name).font(.system(size: 13)).frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surface2)
                            Capsule().fill(Palette.pink).frame(width: geo.size.width * Double(item.count) / top)
                        }
                    }
                    .frame(height: 8)
                    Text("\(item.count)d").font(.system(size: 13)).monospacedDigit().foregroundStyle(Palette.inkSoft).frame(width: 28, alignment: .trailing)
                }
            }
            Text("A personal record you can bring to an appointment. Petal doesn't interpret symptoms.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
        }
        .card()
    }
}
