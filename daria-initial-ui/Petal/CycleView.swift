import SwiftUI

@MainActor
struct CycleView: View {
    @Environment(CycleStore.self) private var store
    @State private var showingCycleDetails = false
    @State private var selectedCycleStart: Date?
    @State private var monthOffset = 0
    @State private var showingMonthPicker = false
    @State private var pickerMonth = 1
    @State private var pickerYear = 2026
    /// Shared with the + button, so a new log goes on the day picked here.
    private var selectedDate: Date { store.selectedCalendarDate ?? store.today }
    private var hasSelectedDate: Bool { store.selectedCalendarDate != nil }
    @State private var showingPeriodControls = false
    @State private var editingPeriod: PeriodRecord?
    @State private var addingPastPeriod: PeriodRecord?
    @State private var periodError: String?
    @State private var deletingPeriod: PeriodRecord?
    @State private var logToDelete: DayLog?
    @State private var insightPage: Int? = 0
    @State private var showingAllSymptoms = false

    var body: some View {
        Page {
            calendar
            insights
            if let error = store.logWriteError { Text(error).font(.caption).foregroundStyle(.red) }
            logHistory
        }
        .sheet(isPresented: $showingPeriodControls) {
            periodControlsSheet
        }
        .sheet(isPresented: $showingCycleDetails) {
            cycleDetails
        }
        .sheet(isPresented: $showingMonthPicker) {
            monthPicker
        }
    }

    private var periodControlsSheet: some View {
        NavigationStack {
            ScrollView {
                periodControls.padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("Track your period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingPeriodControls = false }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: $addingPastPeriod) { draft in
            PastPeriodEditor(start: draft.start).environment(store)
        }
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: selectedDate.formatted(.dateTime.weekday(.wide)))
                Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                    .font(.display(30))
                    .accessibilityAddTraits(.isHeader)
                statusPill
            }

            if let error = store.periodStorageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            VStack(spacing: 0) {
                periodSwitchRow(icon: "drop.fill", title: startSwitchLabel, detail: startDetail, isOn: Binding(
                    get: { displayedStartPeriod != nil },
                    set: { enabled in
                        if enabled {
                            if store.periodHistory.records.contains(where: { $0.start > selectedDate }) {
                                addingPastPeriod = PeriodRecord(start: selectedDate)
                            } else {
                                updatePeriodSwitch { try store.savePeriod(start: selectedDate, end: nil) }
                            }
                        } else if let record = displayedStartPeriod {
                            if record.end != nil {
                                deletingPeriod = record
                            } else {
                                updatePeriodSwitch { try store.removePeriod(id: record.id) }
                            }
                        }
                    }))
                Divider().padding(.leading, 50)
                periodSwitchRow(icon: "checkmark.circle.fill", title: "Period ended \(selectedDayLabel)", detail: endDetail, isOn: Binding(
                    get: { endingPeriod != nil },
                    set: { enabled in
                        if enabled, let record = periodToEnd {
                            updatePeriodSwitch { try store.savePeriod(id: record.id, start: record.start, end: selectedDate) }
                        } else if !enabled, let record = endingPeriod {
                            updatePeriodSwitch { try store.savePeriod(id: record.id, start: record.start, end: nil) }
                        }
                    }))
                    .disabled(periodToEnd == nil && endingPeriod == nil)
            }
            .disabled(store.periodStorageError != nil || isFutureDate)
            .card()

            if isFutureDate {
                Label("Periods can only be recorded for today or earlier.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Your periods",
                              trailing: store.periodHistory.records.isEmpty ? nil : "\(store.periodHistory.records.count) recorded")
                if store.periodHistory.records.isEmpty {
                    Text("No periods recorded yet. Mark a start above, or add one from the past.")
                        .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                }
                ForEach(store.periodHistory.records) { record in periodRow(record) }
                Button {
                    addingPastPeriod = PeriodRecord(start: min(selectedDate, store.today))
                } label: {
                    Label("Add a past period", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Palette.rose.opacity(0.3)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
                .disabled(store.periodStorageError != nil)
                .padding(.top, 4)
            }
        }
        .tint(Palette.accent)
    }

    /// What the selected day is: a recorded period day, a predicted one, or neither.
    private var statusPill: some View {
        let (icon, text, strong): (String, String, Bool) = {
            if let record = displayedStartPeriod {
                let day = CycleStore.days(selectedDate, from: record.start) + 1
                return ("drop.fill", record.end == nil ? "Period day \(day) · ongoing" : "Period day \(day)", true)
            }
            if store.isPredicted(selectedDate) { return ("sparkles", "Predicted period", false) }
            return ("circle.dashed", "No period recorded", false)
        }()
        return Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(strong ? Color.white : Palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(strong ? Palette.accent : Palette.mist, in: Capsule())
    }

    private var startDetail: String {
        if let record = displayedStartPeriod {
            return record.end == nil ? "Ongoing. Turn off to remove this period." : "Turn off to delete this period."
        }
        return "Makes \(store.fmt(selectedDate)) day 1 of a period."
    }

    private var endDetail: String {
        if endingPeriod != nil { return "Last day recorded. Turn off to mark it ongoing again." }
        if let record = periodToEnd { return "Ends the period that started \(store.fmt(record.start))." }
        return "Mark a start on or before this day first."
    }

    private func periodSwitchRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(Palette.accentSoft.opacity(0.6), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail).font(.caption).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 10)
    }

    private func periodRow(_ record: PeriodRecord) -> some View {
        let range = record.end.map { "\(store.fmt(record.start)) – \(store.fmt($0))" } ?? "\(store.fmt(record.start)) – now"
        let days = CycleStore.days(record.end ?? store.today, from: record.start) + 1
        let containsSelected = displayedStartPeriod?.id == record.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(range).font(.system(size: 15, weight: .semibold))
                Text(record.start.formatted(.dateTime.year())).font(.caption).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
            Text(record.end == nil ? "Ongoing" : "\(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Palette.mist, in: Capsule())
            Menu {
                Button("Edit dates", systemImage: "pencil") { editingPeriod = record }
                Button("Delete period", systemImage: "trash", role: .destructive) { deletingPeriod = record }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for period starting \(store.fmt(record.start))")
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(containsSelected ? Palette.accent.opacity(0.5) : Palette.line, lineWidth: containsSelected ? 1.5 : 1))
    }

    // MARK: Calendar

    private var monthPicker: some View {
        let currentYear = CycleStore.cal.component(.year, from: store.today)
        let displayedYear = CycleStore.cal.component(.year, from: month)
        let years = min(currentYear - 100, displayedYear)...max(currentYear + 100, displayedYear)

        return VStack(spacing: 12) {
            HStack {
                Button("Cancel") { showingMonthPicker = false }
                Spacer()
                Text("Choose month").font(.headline)
                Spacer()
                Button("Go") {
                    let current = CycleStore.cal.dateComponents([.year, .month], from: store.today)
                    monthOffset = (pickerYear - current.year!) * 12 + pickerMonth - current.month!
                    showingPeriodControls = false
                    showingMonthPicker = false
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 0) {
                Picker("Month", selection: $pickerMonth) {
                    ForEach(1...12, id: \.self) { value in
                        Text(CycleStore.cal.monthSymbols[value - 1]).tag(value)
                    }
                }
                Picker("Year", selection: $pickerYear) {
                    ForEach(years, id: \.self) { value in
                        Text(String(value)).tag(value)
                    }
                }
            }
            .pickerStyle(.wheel)
            .sensoryFeedback(.selection, trigger: pickerMonth)
            .sensoryFeedback(.selection, trigger: pickerYear)
        }
        .padding(.top, 24)
        .tint(Palette.accent)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private var month: Date {
        let comps = CycleStore.cal.dateComponents([.year, .month], from: store.today)
        let first = CycleStore.cal.date(from: comps)!
        return CycleStore.cal.date(byAdding: .month, value: monthOffset, to: first)!
    }

    private var calendar: some View {
        let cal = CycleStore.cal
        let lead = cal.component(.weekday, from: month) - 1 // Sunday-first
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let cellCount = ((lead + days + 6) / 7) * 7
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)

        return VStack(spacing: 14) {
            HStack {
                circleButton("chevron.left") { monthOffset -= 1 }
                    .accessibilityLabel("Previous month")
                Spacer()
                Button {
                    pickerMonth = cal.component(.month, from: month)
                    pickerYear = cal.component(.year, from: month)
                    showingMonthPicker = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(month.formatted(.dateTime.month(.wide))).font(.display(30))
                        Text(month.formatted(.dateTime.year())).font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.inkFaint)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
                .accessibilityHint("Choose a month and year")
                Spacer()
                circleButton("chevron.right") { monthOffset += 1 }
                    .accessibilityLabel("Next month")
            }
            .padding(.bottom, 4)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                ForEach(0..<cellCount, id: \.self) { i in
                    if i >= lead && i < lead + days {
                        dayCell(CycleStore.add(month, i - lead))
                    } else {
                        Color.clear.frame(height: Self.cellHeight)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .overlay {
                GeometryReader { geometry in
                    Path { path in
                        for row in 0..<(cellCount / 7) {
                            let y = 28 + CGFloat(row) * Self.cellHeight
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(Palette.berry.opacity(0.12), lineWidth: 1)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            HStack(spacing: 14) {
                legend(Rectangle().fill(Palette.mist), "Period")
                legend(Rectangle().fill(Palette.mist.opacity(0.5)), "Predicted")
                legend(Circle().stroke(Palette.accent, lineWidth: 2), "Today")
                legend(Circle().fill(Palette.accent), "Selected")
            }.font(.caption).foregroundStyle(Palette.inkSoft)
            Text("Predictions are estimates. Your period may come a few days earlier or later.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
    }

    /// Calendar rows are tall so the month reads as the page's main element.
    private static let cellHeight: CGFloat = 64

    private func dayCell(_ d: Date) -> some View {
        let day = CycleStore.cal.startOfDay(for: d)
        let completed = store.periodHistory.records.first { record in
            guard let end = record.end else { return false }
            return day >= CycleStore.cal.startOfDay(for: record.start) && day <= CycleStore.cal.startOfDay(for: end)
        }
        let spanStart = completed.map { CycleStore.cal.startOfDay(for: $0.start) } ?? store.expectedPeriodStart(for: day)
        let period = spanStart != nil || store.hasPeriod(on: day)
        // Days of the current period that haven't happened yet count as predicted, like the next period.
        let predicted = (period && day > store.today) || store.isPredicted(day)
        let periodDay = spanStart.map { CycleStore.days(day, from: $0) + 1 }
        let isToday = CycleStore.cal.isDate(day, inSameDayAs: store.today)
        let isSelected = hasSelectedDate && CycleStore.cal.isDate(day, inSameDayAs: selectedDate)
        return Button {
            store.selectedCalendarDate = day
            showingPeriodControls = true
        } label: {
            // A stable row height prevents two-digit dates from being compressed
            // by an aspect-ratio proposal. The entire cell accepts taps.
            Text("\(CycleStore.cal.component(.day, from: day))")
                .font(.system(size: 17, weight: isToday ? .bold : .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? Color.white : Palette.ink)
                .frame(width: 40, height: 40)
                .background {
                    if isSelected { Circle().fill(Palette.accent) }
                    else if isToday { Circle().stroke(Palette.accent, lineWidth: 2) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
                .background {
                    if predicted { Rectangle().fill(Palette.mist.opacity(0.5)) }
                    else if period { Rectangle().fill(Palette.mist) }
                }
                .overlay(alignment: .topLeading) {
                    if let periodDay {
                        Text("\(periodDay)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.leading, 4)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : "")
                            + (predicted ? ", predicted period" : period ? ", period" : "")
                            + (periodDay.map { ", period day \($0)" } ?? ""))
        .accessibilityHint("Opens period start and end controls for this date")
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

    private var recordedCycles: [RecordedCycle] {
        RecordedCycle.recent(from: store.periodHistory.records)
    }

    /// Cycle length, symptom summary and cycle comparison, swiped through one at a time.
    private var insights: some View {
        let current = insightPage ?? 0
        return VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<Self.insightCount, id: \.self) { page in
                        Group {
                            switch page {
                            case 0: lengths
                            case 1: symptoms
                            default: SymptomComparisonView()
                            }
                        }
                        // Stretch to the tallest card so all three match, without a fixed height.
                        .frame(maxHeight: .infinity, alignment: .top)
                        .card()
                        .containerRelativeFrame(.horizontal)
                        .id(page)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $insightPage)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            HStack(spacing: 14) {
                carouselArrow("chevron.left", label: "Previous card", enabled: current > 0) { current - 1 }
                HStack(spacing: 6) {
                    ForEach(0..<Self.insightCount, id: \.self) { page in
                        Capsule()
                            .fill(page == current ? Palette.accent : Palette.accentSoft)
                            .frame(width: page == current ? 18 : 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
                carouselArrow("chevron.right", label: "Next card", enabled: current < Self.insightCount - 1) { current + 1 }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: insightPage)
        }
    }

    private static let insightCount = 3

    private func carouselArrow(_ icon: String, label: String, enabled: Bool, to page: @escaping () -> Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { insightPage = page() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().stroke(Palette.line))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var lengths: some View {
        let cycles = recordedCycles
        let average = cycles.isEmpty ? 0 : Int((Double(cycles.reduce(0) { $0 + $1.days }) / Double(cycles.count)).rounded())
        let maximum = max(cycles.map(\.days).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cycle length", trailing: "saved periods")
            if cycles.isEmpty {
                Text("Save at least two period start dates to see your first cycle length.")
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
                Text("Cycle length is the number of days between consecutive period starts.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(cycles) { cycle in
                        Button {
                            selectedCycleStart = cycle.start
                            showingCycleDetails = true
                        } label: {
                            bar(value: cycle.days, height: CGFloat(cycle.days) / CGFloat(maximum) * 90,
                                label: cycle.start.formatted(.dateTime.month(.abbreviated).day()), highlight: false)
                                .frame(maxWidth: .infinity, minHeight: 130, alignment: .bottom)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cycle starting \(cycle.start.formatted(date: .abbreviated, time: .omitted)), \(cycle.days) days")
                        .accessibilityHint("Shows the saved dates used to calculate this cycle")
                    }
                    Button {
                        selectedCycleStart = nil
                        showingCycleDetails = true
                    } label: {
                        bar(value: average, height: CGFloat(average) / CGFloat(maximum) * 90, label: "Avg", highlight: true)
                            .frame(maxWidth: .infinity, minHeight: 130, alignment: .bottom)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Average \(average) days")
                    .accessibilityHint("Shows the cycles included in the average")
                }
            }
        }
    }

    private var cycleDetails: some View {
        let cycles = recordedCycles
        return NavigationStack {
            List {
                if let start = selectedCycleStart, let cycle = cycles.first(where: { $0.start == start }) {
                    Section("Recorded cycle") {
                        LabeledContent("Cycle length", value: "\(cycle.days) days")
                        LabeledContent("Period started", value: cycle.start.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Next period started", value: cycle.nextStart.formatted(date: .abbreviated, time: .omitted))
                    }
                    Section {
                        Text("\(cycle.days) calendar days between these two saved starts. The next start belongs to the next cycle. This measures cycle length, not the number of bleeding days.")
                    }
                } else if selectedCycleStart == nil, !cycles.isEmpty {
                    let total = cycles.reduce(0) { $0 + $1.days }
                    let average = Int((Double(total) / Double(cycles.count)).rounded())
                    Section("Average cycle length") {
                        LabeledContent("Rounded average", value: "\(average) days")

                    }
                    Section("Included cycles") {
                        ForEach(cycles) { cycle in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(cycle.days) days").font(.headline)
                                Text("\(cycle.start.formatted(date: .abbreviated, time: .omitted)) → \(cycle.nextStart.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
                            }
                        }
                    }
                } else {
                    Text("This cycle is no longer available. Save at least two period starts to see cycle details.")
                }
                Section {
                    Text("Calculated from period dates saved on this device. Missing starts can make intervals longer.")
                }
            }
            .navigationTitle(selectedCycleStart == nil ? "Cycle average" : "Cycle details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingCycleDetails = false }
                }
            }
            .tint(Palette.accent)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private static let symptomPreviewCount = 4

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
            ForEach(counts.prefix(Self.symptomPreviewCount), id: \.name) { item in
                symptomRow(item, top: top)
            }
            if counts.count > Self.symptomPreviewCount {
                Button("See all \(counts.count) symptoms") { showingAllSymptoms = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .sheet(isPresented: $showingAllSymptoms) { allSymptoms }
    }

    private func symptomRow(_ item: (name: String, count: Int), top: Double) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.count) days")
    }

    private var allSymptoms: some View {
        let counts = store.symptomCounts
        let top = Double(counts.first?.count ?? 1)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Days you logged each symptom in the last 60 days.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    ForEach(counts, id: \.name) { item in symptomRow(item, top: top) }
                }
                .card()
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("Symptom summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingAllSymptoms = false }
                }
            }
            .tint(Palette.accent)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                        logToDelete = log
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.accent)
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete log for \(log.date.formatted(date: .abbreviated, time: .omitted))")
                }
                // Only separate entries; nothing after the last one.
                if log.id != recent.last?.id {
                    Divider().overlay(Palette.line)
                }
            }
        }
        .card()
        .confirmationDialog("Delete this saved log?", isPresented: Binding(get: { logToDelete != nil }, set: { if !$0 { logToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete log", role: .destructive) {
                if let logToDelete { store.deleteLog(logToDelete) }
                logToDelete = nil
            }
            Button("Cancel", role: .cancel) { logToDelete = nil }
        } message: {
            Text("This entry will be removed from your symptom history.")
        }
    }
}

@MainActor
private struct PastPeriodEditor: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var start: Date
    @State private var end: Date?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Period started", selection: $start, in: ...Date(), displayedComponents: .date)
                        .onChange(of: start) { _, newStart in
                            if let end, end < newStart { self.end = nil }
                        }
                    if end != nil {
                        DatePicker("Last bleeding day", selection: Binding(
                            get: { end ?? start }, set: { end = $0 }),
                            in: start...max(start, Date()), displayedComponents: .date)
                    } else {
                        Button("Choose last bleeding day") { end = start }
                    }
                } footer: {
                    Text("Enter both dates for the period you missed. Nothing is saved until you tap Save. Use your actual last bleeding day, including the same day for a one-day period.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add past period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let end else { return }
                        do {
                            try store.savePeriod(start: start, end: end)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(end == nil || store.periodStorageError != nil)
                }
            }
            .tint(Palette.accent)
        }
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
