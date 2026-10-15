import SwiftUI

struct CycleView: View {
    @Environment(CycleStore.self) private var store
    @State private var monthOffset = 0
    @State private var confirmingDelete = false
    @State private var logToDelete: UUID?
    @State private var confirmingLogDelete = false

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Your cycle")
                DisplayTitle(before: "Patterns, ", accent: "not", after: " promises")
            }
            calendar
            lengths
            symptoms
            logHistory
            dataCard
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
        let values = Array(store.pastLengths.reversed())
        let height = { (v: Int) in CGFloat(v - 20) / 14 * 90 }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cycle length", trailing: "last 5 cycles")
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    bar(value: v, height: height(v), label: store.starts[values.count - i].formatted(.dateTime.month(.abbreviated)), highlight: false)
                }
                bar(value: store.average, height: height(store.average), label: "Avg", highlight: true)
            }
            .frame(height: 130, alignment: .bottom)
            Text("Your cycles vary by about \(store.pastLengths.max()! - store.pastLengths.min()!) days, which is common. If they start varying by more than 7–9 days, it may be worth mentioning to a doctor.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
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

    // MARK: Saved log history (HACK-1)

    private var logHistory: some View {
        let recent = Array(store.logs.sorted { $0.date > $1.date }.prefix(20))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Saved day logs", trailing: "\(store.logs.count) entries")
            if recent.isEmpty {
                Text("No logs yet. Tap + to record your day.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSoft)
            }
            ForEach(recent) { log in
                HStack(spacing: 12) {
                    Button {
                        store.selectedLogDate = log.date
                        store.showLog = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.system(size: 14, weight: .semibold))
                            Text(([log.flow != "None" ? "Flow: \(log.flow)" : ""]
                                + log.symptoms).filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.inkSoft)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button {
                        logToDelete = log.id
                        confirmingLogDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.accent)
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete log for \(log.date.formatted(date: .abbreviated, time: .omitted))")
                }
                Divider().overlay(Palette.line)
            }
        }
        .card()
        .confirmationDialog("Delete this saved log?", isPresented: $confirmingLogDelete, titleVisibility: .visible) {
            Button("Delete log", role: .destructive) {
                if let logToDelete { store.deleteLog(id: logToDelete) }
                logToDelete = nil
            }
            Button("Cancel", role: .cancel) { logToDelete = nil }
        } message: {
            Text("This entry will be removed from your symptom history.")
        }
    }

    // MARK: Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your data")
            Text("Logs are saved on this device. You can delete entries or clear saved logs and in-app selections. Fictional demo cycle dates may still display in this prototype.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
            if confirmingDelete {
                Text("This clears saved day logs and in-app selections. Demo cycle dates are not removed in this prototype.")
                    .font(.system(size: 13))
                HStack {
                    outlineButton("Erase everything") { store.deleteAllData(); confirmingDelete = false }
                    Button("Keep my data") { confirmingDelete = false }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Palette.surface2, in: Capsule())
                        .buttonStyle(.plain)
                }
            } else {
                outlineButton("Delete all my data") { confirmingDelete = true }
            }
        }
        .card()
        .animation(.easeOut(duration: 0.2), value: confirmingDelete)
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
