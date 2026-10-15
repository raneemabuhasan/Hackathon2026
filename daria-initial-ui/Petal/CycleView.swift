import SwiftUI

struct CycleView: View {
    @Environment(CycleStore.self) private var store
    @State private var monthOffset = 0
    @State private var confirmingDelete = false
    @State private var managingPeriods = false

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Your cycle")
                DisplayTitle(before: "Patterns, ", accent: "not", after: " promises")
            }
            Button("Record / edit period dates") { managingPeriods = true }
                .buttonStyle(.bordered)
            calendar
            lengths
            historyEntries
            symptoms
            SymptomComparisonView()
            dataCard
        }
        .sheet(isPresented: $managingPeriods) { PeriodHistoryView().environment(store) }
    }

    private var historyEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Daily entries")
            if store.logs.isEmpty { Text("No entries yet. Tap + to record a day.") }
            ForEach(store.logs.sorted { $0.date > $1.date }) { log in
                DisclosureGroup(log.date.formatted(date: .abbreviated, time: .omitted)) {
                    Text(log.symptoms.joined(separator: ", "))
                    Text(log.note)
                    Button("Edit entry") { store.editingLog = log; store.showLog = true }
                }
            }
        }.card()
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
                legend(Circle().strokeBorder(Palette.pink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])), "Estimated start")
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recorded cycle lengths")
            if store.pastLengths.isEmpty {
                Text("Record two period start dates to see a start-to-start interval.")
            }
            ForEach(Array(store.pastLengths.enumerated()), id: \.offset) { index, length in
                Text("Interval \(index + 1), most recent first: \(length) days")
            }
            Text("These are intervals between recorded starts; missing records may affect them.").font(.caption)
        }.card()
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

    // MARK: Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your data")
            Text("History is saved on this device. No cloud sync is connected.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
            if confirmingDelete {
                Text("This permanently clears your period dates, symptom history and saved preferences.")
                    .font(.system(size: 13))
                HStack {
                    outlineButton("Delete all data") { store.deleteAllData(); confirmingDelete = false }
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
