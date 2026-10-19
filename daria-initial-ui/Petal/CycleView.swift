import SwiftUI

@MainActor
struct CycleView: View {
    @Environment(CycleStore.self) private var store
    @State private var monthOffset = 0
    @State private var confirmingDelete = false
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var showingPeriodControls = false
    @State private var showingPeriodHistory = false
    @State private var editingLoggedPeriod: LoggedPeriod?
    @State private var editingPeriod: PeriodRecord?
    @State private var periodError: String?
    @State private var deletingPeriod: PeriodRecord?
    @State private var logToDelete: DayLog?
    @State private var searchExpanded = false
    @State private var historyQuery = ""
    @State private var historyField: HistoryField = .all
    @State private var historyDateRange: HistoryDateRange = .all
    @State private var monthExpansion: [Date: Bool] = [:]
    @FocusState private var isHistorySearchFocused: Bool

    private enum HistoryField: String, CaseIterable, Identifiable {
        case all = "All fields"
        case symptoms = "Symptoms"
        case moods = "Moods"
        case flow = "Flow"
        case notes = "Notes"

        var id: String { rawValue }
    }

    private enum HistoryDateRange: String, CaseIterable, Identifiable {
        case all = "All time"
        case month = "This month"
        case quarter = "Last 3 months"
        case year = "Last 12 months"

        var id: String { rawValue }

        func includes(_ date: Date, today: Date, calendar: Calendar = .current) -> Bool {
            if self == .all { return true }
            let thisMonth = calendar.dateInterval(of: .month, for: today)?.start
                ?? calendar.startOfDay(for: today)
            let monthsBack: Int
            switch self {
            case .all: monthsBack = 0
            case .month: monthsBack = 0
            case .quarter: monthsBack = 2
            case .year: monthsBack = 11
            }
            let firstDay = calendar.date(byAdding: .month, value: -monthsBack, to: thisMonth)
                ?? thisMonth
            let day = calendar.startOfDay(for: date)
            return day >= firstDay && day <= calendar.startOfDay(for: today)
        }
    }

    private struct HistoryMonth: Identifiable {
        let date: Date
        let logs: [DayLog]
        var id: Date { date }
    }

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Your cycle")
                DisplayTitle(before: "Patterns, ", accent: "not", after: " promises")
            }
            calendar
            // The compact editor stays available under the calendar even when collapsed.
            periodControls
            Text("Cycle charts and summaries use your saved logs. Predictions are estimates.").font(.caption).foregroundStyle(Palette.inkSoft)
            lengths
            symptoms
            logHistory
        }
        .scrollDismissesKeyboard(.never)
        .sheet(item: $editingPeriod) { record in
            PeriodEditor(record: record).environment(store)
        }
        .sheet(item: $editingLoggedPeriod) { period in
            LoggedPeriodEditor(period: period).environment(store)
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

    private var loggedPeriodAtSelectedDate: LoggedPeriod? {
        store.loggedPeriod(on: selectedDate)
    }

    private var loggedPeriodEndingHere: LoggedPeriod? {
        store.loggedPeriods.first { inferred in
            guard let end = inferred.end else { return false }
            if Calendar.current.isDate(end, inSameDayAs: selectedDate) { return true }
            // The first explicit None day confirms that the LAST bleeding day was the end.
            return store.log(for: selectedDate)?.flow == "None"
                && Calendar.current.isDate(CycleStore.add(end, 1), inSameDayAs: selectedDate)
        }
    }

    private var endSwitchLabel: String {
        if let saved = endingPeriod, let end = saved.end { return "Period ended " + store.fmt(end) }
        if let logged = loggedPeriodEndingHere, let end = logged.end {
            return "Period ended " + store.fmt(end)
        }
        return "Period ended " + selectedDayLabel
    }

    private var startSwitchLabel: String {
        if let record = displayedStartPeriod {
            return "Period started on " + store.fmt(record.start)
        }
        if let inferred = loggedPeriodAtSelectedDate {
            return "Period started on " + store.fmt(inferred.start)
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
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingPeriodControls.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Palette.accent)
                    Text("Track your period")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    Image(systemName: showingPeriodControls ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(Palette.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(showingPeriodControls ? "Collapse period controls" : "Expand period controls")

            if showingPeriodControls {
                if isFutureDate {
                    Text("Choose today or a previous day to record a period.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                }
                if let error = periodError ?? store.periodStorageError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                VStack(spacing: 12) {
                    Toggle(startSwitchLabel, isOn: Binding(
                        get: { displayedStartPeriod != nil || loggedPeriodAtSelectedDate != nil },
                        set: { enabled in
                            if let inferred = loggedPeriodAtSelectedDate, displayedStartPeriod == nil {
                                // Let people correct detected dates instead of disabling this switch.
                                editingLoggedPeriod = inferred
                            } else if enabled {
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
                    Toggle(endSwitchLabel, isOn: Binding(
                        get: { endingPeriod != nil || loggedPeriodEndingHere != nil },
                        set: { enabled in
                            if let inferred = loggedPeriodAtSelectedDate ?? loggedPeriodEndingHere,
                               endingPeriod == nil {
                                editingLoggedPeriod = inferred
                            } else if enabled {
                                if let record = periodToEnd {
                                    updatePeriodSwitch { try store.savePeriod(id: record.id, start: record.start, end: selectedDate) }
                                } else {
                                    periodError = "Mark a period start on this date or an earlier date first."
                                }
                            } else if let record = endingPeriod {
                                updatePeriodSwitch { try store.savePeriod(id: record.id, start: record.start, end: nil) }
                            }
                        }))
                }
                .toggleStyle(.switch)
                .disabled(store.periodStorageError != nil || isFutureDate)

                if let inferred = loggedPeriodAtSelectedDate ?? loggedPeriodEndingHere,
                   displayedStartPeriod == nil {
                    Button {
                        editingLoggedPeriod = inferred
                    } label: { Label("Edit dates", systemImage: "calendar.badge.clock") }
                        .font(.system(size: 13, weight: .semibold))
                    Text("Detected from flow logs. Calendar dates can be corrected without changing saved logs.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                } else if let manual = displayedStartPeriod ?? endingPeriod {
                    Button { editingPeriod = manual } label: {
                        Label("Edit dates", systemImage: "calendar.badge.clock")
                    }
                    .font(.system(size: 13, weight: .semibold))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingPeriodHistory.toggle() }
                } label: {
                    HStack {
                        Text("Saved periods").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: showingPeriodHistory ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.inkSoft)
                if showingPeriodHistory {
                    if store.periodHistory.records.isEmpty && store.loggedPeriods.isEmpty {
                        Text("No periods recorded yet.").font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    ForEach(store.periodHistory.records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.start.formatted(date: .abbreviated, time: .omitted))
                                Text(record.end.map { "Through " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "Ongoing")
                                    .font(.caption).foregroundStyle(Palette.inkSoft)
                            }
                            Spacer()
                            Button("Edit") { editingPeriod = record }
                            Button(role: .destructive) { deletingPeriod = record } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete period starting \(store.fmt(record.start))")
                        }
                    }
                    ForEach(store.loggedPeriods.filter { inferred in
                        !store.periodHistory.records.contains { manual in
                            let manualEnd = manual.end ?? CycleStore.add(manual.start, 9)
                            return manual.start <= inferred.visibleEnd && inferred.start <= manualEnd
                        }
                    }) { inferred in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(inferred.start.formatted(date: .abbreviated, time: .omitted))
                                Text(inferred.end.map { "Through " + $0.formatted(date: .abbreviated, time: .omitted) }
                                     ?? "Flow logged through " + inferred.lastFlow.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(Palette.inkSoft)
                            }
                            Spacer()
                            Button("Edit") { editingLoggedPeriod = inferred }
                        }
                    }
                }
                Text("Switches save calendar dates immediately. Edit dates opens Save/Cancel. Calendar corrections stay on this device.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
            }
        }
        .card()
        .tint(Palette.accent)
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
        let savedLog = store.log(for: d)
        let period = store.isRecordedPeriod(d)
        let manuallyRecorded = store.periodHistory.records.first { record in
            d >= CycleStore.cal.startOfDay(for: record.start)
                && d <= CycleStore.cal.startOfDay(for: record.end ?? record.start)
        }
        let fromLog = store.loggedPeriod(on: d)
        let isStart = (manuallyRecorded.map { CycleStore.cal.isDate(d, inSameDayAs: $0.start) } ?? false)
            || (fromLog.map { CycleStore.cal.isDate(d, inSameDayAs: $0.start) } ?? false)
        let isEnd = (manuallyRecorded?.end.map { CycleStore.cal.isDate(d, inSameDayAs: $0) } ?? false)
            || (fromLog?.end.map { CycleStore.cal.isDate(d, inSameDayAs: $0) } ?? false)
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
                    if period {
                        Rectangle().fill(Palette.pink)
                            .frame(height: 4)
                            .padding(.leading, isStart ? 8 : 0)
                            .padding(.trailing, isEnd ? 8 : 0)
                            .padding(.bottom, 3)
                            .allowsHitTesting(false)
                    } else if savedLog != nil {
                        Circle().fill(Color.gray.opacity(0.65))
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

    // MARK: Searchable, month-grouped symptom history

    private var historyQueryText: String {
        historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var historyFiltersActive: Bool {
        !historyQueryText.isEmpty || historyDateRange != .all || historyField != .all
    }

    /// Apply filters to *all* saved logs. Nothing is truncated to 20 days.
    private var matchingHistoryLogs: [DayLog] {
        store.logs.filter { log in
            guard historyDateRange.includes(log.date, today: store.today) else { return false }
            let query = historyQueryText
            guard !query.isEmpty else { return true }

            let fields: [String]
            switch historyField {
            case .all:
                fields = log.symptoms + log.moods + [log.flow, log.note]
            case .symptoms:
                fields = log.symptoms
            case .moods:
                fields = log.moods
            case .flow:
                fields = [log.flow]
            case .notes:
                fields = [log.note]
            }
            return fields.contains { $0.localizedStandardContains(query) }
        }
        .sorted { $0.date > $1.date }
    }

    private var historyMonths: [HistoryMonth] {
        let calendar = Calendar.current
        let byMonth = Dictionary(grouping: matchingHistoryLogs) { log in
            calendar.dateInterval(of: .month, for: log.date)?.start
                ?? calendar.startOfDay(for: log.date)
        }
        return byMonth.keys.sorted(by: >).map { month in
            HistoryMonth(date: month, logs: byMonth[month] ?? [])
        }
    }

    /// Suggestions use saved tag names, never the contents of private notes.
    private var historySuggestions: [String] {
        // Suggestions follow the date filter, not every log ever recorded.
        let relevantLogs = store.logs.filter { historyDateRange.includes($0.date, today: store.today) }
        let values: [String]
        switch historyField {
        case .all:
            values = relevantLogs.flatMap { $0.symptoms + $0.moods }
        case .symptoms:
            values = relevantLogs.flatMap { $0.symptoms }
        case .moods:
            values = relevantLogs.flatMap { $0.moods }
        case .flow:
            values = relevantLogs.map(\.flow).filter { $0 != "None" }
        case .notes:
            return []
        }
        let nonempty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let grouped = Dictionary(grouping: nonempty, by: { $0.lowercased() })
        return grouped.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs.first ?? "") < (rhs.first ?? "")
        }
        .compactMap { $0.first }
        .filter { historyQueryText.isEmpty || $0.localizedStandardContains(historyQueryText) }
        .prefix(8)
        .map { $0 }
    }

    // Browsing expands one month at a time. Search results can keep many months open.
    @State private var browsedHistoryMonth: Date?

    private func historyMonthIsOpen(_ date: Date, newest: Date?) -> Bool {
        if historyQueryText.isEmpty { return browsedHistoryMonth == date }
        return monthExpansion[date] ?? (date == newest)
    }

    /// A seven-calendar-day preview that respects the active search and date filters.
    private var recentHistoryLogs: [DayLog] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.today)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return matchingHistoryLogs.filter { log in
            let day = calendar.startOfDay(for: log.date)
            return day >= start && day <= today
        }
    }

    private var historySuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(historyField == .symptoms ? "Suggested symptoms" :
                 historyField == .moods ? "Suggested moods" :
                 historyField == .flow ? "Suggested flows" : "Suggested symptoms & moods")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkFaint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(historySuggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            historyQuery = suggestion
                            isHistorySearchFocused = false
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Palette.surface2, in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityHint("Search logs for \(suggestion)")
                    }
                }
            }
        }
    }

    private func clearHistoryFilters() {
        historyQuery = ""
        historyField = .all
        historyDateRange = .all
        isHistorySearchFocused = false
        monthExpansion = [:] // Reset expanded search months.
        browsedHistoryMonth = nil
    }

    private var logHistory: some View {
        let months = historyMonths
        let count = matchingHistoryLogs.count

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Saved day logs", trailing: "\(store.logs.count) entries")

            // The one-line search is always available. Advanced controls stay optional.
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.inkFaint)
                TextField("Search symptoms, moods or notes", text: $historyQuery)
                    .font(.system(size: 13))
                    .focused($isHistorySearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { isHistorySearchFocused = false }
                    .accessibilityLabel("Search saved history")
                if !historyQuery.isEmpty {
                    Button {
                        historyQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search text")
                }
                Button {
                    isHistorySearchFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) { searchExpanded.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 36, height: 36)
                        .background(Palette.mist.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(searchExpanded ? "Hide advanced filters" : "Show advanced filters")
            }
            .padding(.leading, 11)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            // Light search field; month headings use the previous deeper search tint.
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12))

            if isHistorySearchFocused && !searchExpanded && !historySuggestions.isEmpty {
                historySuggestionsPanel
            }

            if historyFiltersActive {
                HStack {
                    Text("\(count) of \(store.logs.count) logs match")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Button("Clear filters") { clearHistoryFilters() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
            }

            if searchExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(HistoryField.allCases) { field in
                                Button {
                                    historyField = field
                                } label: {
                                    if historyField == field {
                                        Label(field.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(field.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Label(historyField.rawValue, systemImage: "line.3.horizontal.decrease")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(Palette.surface2, in: Capsule())
                        }
                        .accessibilityLabel("Search in \(historyField.rawValue)")

                        Menu {
                            ForEach(HistoryDateRange.allCases) { range in
                                Button {
                                    historyDateRange = range
                                } label: {
                                    if historyDateRange == range {
                                        Label(range.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(range.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Label(historyDateRange.rawValue, systemImage: "calendar")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(Palette.surface2, in: Capsule())
                        }
                        .accessibilityLabel("Date range: \(historyDateRange.rawValue)")
                        Spacer(minLength: 0)
                        Button("Reset") { clearHistoryFilters() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .accessibilityLabel("Reset to All fields and All time")
                    }

                    if historyField == .notes {
                        Text("Search for a word from your notes. Note text stays hidden in the list.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkFaint)
                    } else if !historySuggestions.isEmpty {
                        historySuggestionsPanel
                    }
                }
                .padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                .transition(.opacity)
            }

            if store.logs.isEmpty {
                Text("No logs yet. Tap + to record your day.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSoft)
            } else {
                if months.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No matching logs found.")
                            .font(.system(size: 13, weight: .medium))
                        Text("Try another symptom, a different date range, or clear your filters.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkSoft)
                        Button("Clear filters") { clearHistoryFilters() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                } else {
                    // Recent is for unfiltered browsing only; search results live under the month headings.
                    // Opening any month hides it; clearing filters and closing months restores it.
                    let anyMonthOpen = months.contains { historyMonthIsOpen($0.date, newest: months.first?.date) }
                    if !anyMonthOpen && !historyFiltersActive {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Recent", trailing: "Past 7 days")
                            if recentHistoryLogs.isEmpty {
                                Text("No matching logs in the past 7 days. Open a month to browse older entries.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.inkSoft)
                            } else {
                                ForEach(recentHistoryLogs) { log in
                                    historyLogRow(log)
                                }
                            }
                        }
                        .padding(.bottom, 5)
                    }

                    Text("Browse by month")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)

                    ForEach(months) { month in
                        let open = historyMonthIsOpen(month.date, newest: months.first?.date)
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if historyQueryText.isEmpty {
                                        browsedHistoryMonth = open ? nil : month.date
                                    } else {
                                        monthExpansion[month.date] = !open
                                    }
                                }
                                isHistorySearchFocused = false
                            } label: {
                                HStack(spacing: 8) {
                                    Text(month.date.formatted(.dateTime.month(.wide).year()))
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\(month.logs.count) \(month.logs.count == 1 ? "log" : "logs")")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.inkSoft)
                                    Spacer()
                                    Image(systemName: open ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(Palette.ink)
                                .padding(11)
                                .background(Palette.mist.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(open ? "Collapse this month" : "Expand this month")

                            if open {
                                ForEach(month.logs) { log in
                                    historyLogRow(log)
                                }
                            }
                        }
                    }
                }
            }
        }
        .card()
        .onChange(of: historyDateRange) { _, _ in monthExpansion = [:] }
        .onChange(of: historyField) { _, _ in monthExpansion = [:] }
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

    /// Shared row for Recent and month sections. Note text is never shown in previews.
    private func historyLogRow(_ log: DayLog) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    store.selectedLogDate = log.date
                    store.showLog = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 14, weight: .semibold))
                        let periodMarked = store.periodHistory.contains(log.date)
                        let details = ([log.flow != "None" ? "Flow: \(log.flow)" :
                                        (periodMarked ? "Period marked" : "")]
                            + log.symptoms + log.moods).filter { !$0.isEmpty }
                        Text(details.isEmpty ? (log.note.isEmpty ? "Daily check-in" : "Note saved")
                             : details.joined(separator: " · "))
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
            Divider().overlay(Palette.line)
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

@MainActor
private struct LoggedPeriodEditor: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let period: LoggedPeriod
    @State private var start: Date
    @State private var end: Date
    @State private var hasEnded: Bool
    @State private var error: String?

    init(period: LoggedPeriod) {
        self.period = period
        _start = State(initialValue: period.start)
        _end = State(initialValue: period.end ?? period.lastFlow)
        _hasEnded = State(initialValue: period.end != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Calendar dates") {
                    DatePicker("Period started", selection: $start, in: ...store.today,
                               displayedComponents: .date)
                    Toggle("Period has ended", isOn: $hasEnded)
                    if hasEnded {
                        DatePicker("Last bleeding day", selection: $end, in: ...store.today,
                                   displayedComponents: .date)
                    }
                }
                Text("These corrections change calendar markings only. Your saved flow logs remain unchanged.")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if store.hasLoggedPeriodAdjustment(period) {
                    Button("Reset to dates from logs") {
                        store.resetLoggedPeriodDates(period)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit period dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.saveLoggedPeriodDates(period, start: start, end: hasEnded ? end : nil)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}
