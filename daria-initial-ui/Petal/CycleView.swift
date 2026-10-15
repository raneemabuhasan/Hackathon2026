import SwiftUI

@MainActor
struct CycleView: View {
    @Environment(CycleStore.self) private var store
    @State private var monthOffset = 0
    @State private var confirmingDelete = false
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var showingPeriodControls = false
    @State private var editingPeriod: PeriodRecord?
    @State private var periodError: String?
    @State private var deletingPeriod: PeriodRecord?
    @State private var interactionFrames: [String: CGRect] = [:]

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Your cycle")
                DisplayTitle(before: "Patterns, ", accent: "not", after: " promises")
            }
            calendar
                .background(interactionBounds("calendar"))
            if showingPeriodControls {
                periodControls
                    .background(interactionBounds("controls"))
            }
            Text("Demo insights below use fictional cycle and symptom data, not your saved periods.").font(.caption).foregroundStyle(Palette.inkSoft)
            lengths
            symptoms
            dataCard
        }
        .coordinateSpace(name: "periodCalendarPage")
        .onPreferenceChange(PeriodInteractionBounds.self) { interactionFrames = $0 }
        // Observe taps without intercepting the calendar buttons or switches.
        // Calendar taps select another day; only taps outside both regions dismiss.
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("periodCalendarPage"))
            .onEnded { event in
                if showingPeriodControls && !interactionFrames.values.contains(where: { $0.contains(event.location) }) {
                    showingPeriodControls = false
                }
            })
        .sheet(item: $editingPeriod) { record in
            PeriodEditor(record: record).environment(store)
        }
        .alert("Could not save period", isPresented: Binding(get: { periodError != nil }, set: { if !$0 { periodError = nil } })) {
            Button("OK") { periodError = nil }
        } message: { Text(periodError ?? "") }
        .confirmationDialog("Delete this entire period, including its start and end dates?", isPresented: Binding(get: { deletingPeriod != nil }, set: { if !$0 { deletingPeriod = nil } }), titleVisibility: .visible) {
            Button("Delete period", role: .destructive) {
                if let record = deletingPeriod { performPeriodAction { try store.removePeriod(id: record.id) } }
                deletingPeriod = nil
            }
        }
    }

    private func interactionBounds(_ region: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: PeriodInteractionBounds.self,
                value: [region: geometry.frame(in: .named("periodCalendarPage"))])
        }
    }

    private func performPeriodAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch { periodError = error.localizedDescription }
    }

    private var isFutureDate: Bool {
        Calendar.current.startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date())
    }

    private var selectedDayLabel: String {
        Calendar.current.isDateInToday(selectedDate) ? "today" : "on " + store.fmt(selectedDate)
    }

    private var startingPeriod: PeriodRecord? {
        store.periodHistory.records.first { Calendar.current.isDate($0.start, inSameDayAs: selectedDate) }
    }

    // Keep the saved start visible while choosing an ongoing period's end,
    // or when inspecting a day inside an already completed period.
    private var displayedStartPeriod: PeriodRecord? {
        let day = Calendar.current.startOfDay(for: selectedDate)
        return store.periodHistory.records.first { record in
            let start = Calendar.current.startOfDay(for: record.start)
            return start <= day && (record.end.map { day <= Calendar.current.startOfDay(for: $0) } ?? true)
        }
    }

    private var startSwitchLabel: String {
        if let record = displayedStartPeriod {
            return "Period started on " + store.fmt(record.start)
        }
        return "Period started " + selectedDayLabel
    }

    private var endingPeriod: PeriodRecord? {
        store.periodHistory.records.first { record in
            record.end.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? false
        }
    }

    private var activePeriod: PeriodRecord? {
        store.periodHistory.records.first { $0.end == nil }
    }

    // Resolve the period for this date, including an already-ended record
    // so a user can correct its end without first reopening it elsewhere.
    private var periodToEnd: PeriodRecord? {
        let day = Calendar.current.startOfDay(for: selectedDate)
        let candidates = store.periodHistory.records.sorted { $0.start > $1.start }
        return candidates.first { Calendar.current.startOfDay(for: $0.start) <= day }
    }

    private func updatePeriodSwitch(_ action: () throws -> Void) {
        do {
            try action()
        } catch { periodError = error.localizedDescription }
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { showingPeriodControls = false }
            }
            SectionHeader(title: "Track your period")
            Text("Tap another date on the calendar above to mark your start or end. These controls stay open until you tap Done or outside.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if isFutureDate {
                Text("This date is in the future. You can browse it, but mark actual period dates once they happen.")
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
            }
            if let active = activePeriod {
                Text("Period started \(store.fmt(active.start)). No end date recorded yet.")
                    .font(.subheadline).foregroundStyle(Palette.accent)
            }
            Text("Choose your actual last bleeding day. There is no fixed period length or estimated end date.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if let error = store.periodStorageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            VStack(spacing: 16) {
                Toggle(startSwitchLabel, isOn: Binding(
                    get: { displayedStartPeriod != nil },
                    set: { enabled in
                        if enabled {
                            updatePeriodSwitch { try store.savePeriod(start: selectedDate, end: nil) }
                        } else if let record = displayedStartPeriod {
                            if record.end != nil {
                                deletingPeriod = record
                            } else {
                                updatePeriodSwitch { try store.removePeriod(id: record.id) }
                            }
                        }
                    }))
                Divider()
                Toggle("Period ended \(selectedDayLabel)", isOn: Binding(
                    get: { endingPeriod != nil },
                    set: { enabled in
                        if enabled {
                            if let record = periodToEnd {
                                updatePeriodSwitch { try store.savePeriod(id: record.id, start: record.start, end: selectedDate) }
                            } else {
                                periodError = "Mark a period start on this date or an earlier date first."
                            }
                        } else if !enabled, let record = endingPeriod {
                            updatePeriodSwitch { try store.savePeriod(id: record.id, start: record.start, end: nil) }
                        }
                    }))

            }
            .toggleStyle(.switch)
            .disabled(store.periodStorageError != nil || isFutureDate)
            Text("Changes save automatically. Turning off a start removes that period; turning off an end marks it ongoing again.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if periodToEnd == nil && endingPeriod == nil {
                Text("Mark a start date before marking an end.").font(.caption).foregroundStyle(Palette.inkSoft)
            }
            if store.periodHistory.records.isEmpty {
                Text("No periods recorded yet.").font(.caption)
            }
            ForEach(store.periodHistory.records) { record in
                HStack {
                    VStack(alignment: .leading) {
                        Text(record.start.formatted(date: .abbreviated, time: .omitted))
                        Text(record.end.map { "Through " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "Ongoing")
                            .font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    Button("Edit") { editingPeriod = record }
                    Button(role: .destructive) { deletingPeriod = record } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete period starting \(store.fmt(record.start))")
                }
            }
            Text("Period dates are saved on this device. Other screens still use demo data.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
        }.card().tint(Palette.accent)
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
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let cellCount = ((lead + days + 6) / 7) * 7
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)

        return VStack(spacing: 14) {
            HStack {
                circleButton("chevron.left") { monthOffset -= 1 }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 15, weight: .semibold))
                Spacer()
                circleButton("chevron.right") { monthOffset += 1 }
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                }
                ForEach(0..<cellCount, id: \.self) { i in
                    if i >= lead && i < lead + days {
                        dayCell(CycleStore.add(month, i - lead))
                    } else {
                        Color.clear.frame(height: 52)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            HStack(spacing: 14) {
                legend(Rectangle().fill(Palette.pink).frame(height: 4), "Recorded period")
                legend(Circle().strokeBorder(Palette.ink, lineWidth: 2), "Today")
            }.font(.caption).foregroundStyle(Palette.inkSoft)
        }
        .card()
    }

    private func dayCell(_ d: Date) -> some View {
        let period = store.periodHistory.contains(d)
        let completed = store.periodHistory.records.first { record in
            guard let end = record.end else { return false }
            return d >= CycleStore.cal.startOfDay(for: record.start) && d <= CycleStore.cal.startOfDay(for: end)
        }
        let isStart = completed.map { CycleStore.cal.isDate(d, inSameDayAs: $0.start) } ?? false
        let isEnd = completed?.end.map { CycleStore.cal.isDate(d, inSameDayAs: $0) } ?? false
        let isToday = CycleStore.cal.isDate(d, inSameDayAs: store.today)
        let isSelected = CycleStore.cal.isDate(d, inSameDayAs: selectedDate)
        return Button {
            selectedDate = CycleStore.cal.startOfDay(for: d)
            showingPeriodControls = true
        } label: {
            // A stable row height prevents two-digit dates from being compressed
            // by an aspect-ratio proposal. The entire cell accepts taps.
            Text("\(CycleStore.cal.component(.day, from: d))")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Palette.ink)
                .overlay(alignment: .bottom) {
                    if completed != nil {
                        Rectangle().fill(Palette.pink)
                            .frame(height: 4)
                            .padding(.leading, isStart ? 8 : 0)
                            .padding(.trailing, isEnd ? 8 : 0)
                            .padding(.bottom, 3)
                            .allowsHitTesting(false)
                    } else if period {
                        Circle().fill(Palette.accent)
                            .frame(width: 5, height: 5)
                            .padding(.bottom, 3)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .overlay {
                    Circle().strokeBorder(Palette.ink, lineWidth: 2)
                        .padding(4)
                        .opacity(isToday ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(d.formatted(date: .complete, time: .omitted) + (period ? ", recorded period" : ""))
        .accessibilityHint("Select this date to mark a period start or end")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    // MARK: Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your data")
            Text("Logs stay on this device. Nothing is shared or sold. You can erase everything at any time.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
            if confirmingDelete {
                Text("This erases every log and preference on this device. It can't be undone.")
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

@MainActor
private struct PeriodEditor: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: PeriodRecord
    @State private var start: Date
    @State private var end: Date
    @State private var ended: Bool
    @State private var error: String?

    init(record: PeriodRecord) {
        self.record = record
        _start = State(initialValue: record.start)
        _end = State(initialValue: record.end ?? Date())
        _ended = State(initialValue: record.end != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, in: ...Date(), displayedComponents: .date)
                Toggle("Period has ended", isOn: $ended)
                if ended { DatePicker("Last bleeding day", selection: $end, in: ...Date(), displayedComponents: .date) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.savePeriod(id: record.id, start: start, end: ended ? end : nil)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}

// Frames stay current when the page scrolls or the controls change height.
private struct PeriodInteractionBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
