import SwiftUI

private struct InsightContentHeight: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

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
    @State private var pendingLogPreview: Date?
    @State private var periodError: String?
    @State private var deletingPeriod: PeriodRecord?
    @State private var insightPage: Int? = 0
    @State private var insightContentHeights: [Int: CGFloat] = [:]
    @State private var showingAllLogs = false
    @State private var periodSearch = ""
    /// What a row tapped in the View more sheet should open once the sheet is gone.
    @State private var afterAllLogs: (() -> Void)?
    @State private var showingAllSymptoms = false

    var body: some View {
        Page(bottomPadding: 24) {
            calendar
            if hasSelectedDate,
               Calendar.current.isDate(selectedDate, equalTo: month, toGranularity: .month),
               let entry = store.log(for: selectedDate) {
                calendarLogPreview(entry)
            }
            insights
            if let error = store.logWriteError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        // Another screen (e.g. Today's prediction card) can pick a date; show its month.
        .onAppear { showSelectedMonth() }
        .onChange(of: store.selectedCalendarDate) { _, _ in showSelectedMonth() }
        .sheet(isPresented: $showingPeriodControls, onDismiss: {
            if let date = pendingLogPreview {
                pendingLogPreview = nil
                openLogPreview(on: date)
            }
        }) {
            periodControlsSheet
        }
        .sheet(isPresented: $showingAllLogs, onDismiss: {
            periodSearch = ""
            afterAllLogs?()
            afterAllLogs = nil
        }) {
            NavigationStack {
                ScrollView {
                    allPeriods
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Palette.bg)
                .navigationTitle("\(store.bleedTitle) history")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAllLogs = false } }
                }
            }
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showingCycleDetails) {
            cycleDetails
        }
        .sheet(isPresented: $showingMonthPicker) {
            monthPicker
        }
    }

    /// One card: the bleed this day belongs to, editable in place, then what was logged that day.
    private var periodControlsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(eyebrow: selectedDate.formatted(.dateTime.weekday(.wide))) {
                showingPeriodControls = false
            } title: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                        .font(.display(28))
                        .accessibilityAddTraits(.isHeader)
                    statusPill
                }
            }

            if let error = store.periodStorageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 0) {
                bleedRows
                    .disabled(store.periodStorageError != nil)
                if !isFutureDate {
                    Divider().overlay(Palette.line).padding(.vertical, 12)
                    dayLogSummary
                }
            }
            .card()

            if let record = displayedStartPeriod, !isFutureDate {
                Button("Delete \(store.bleedName)", systemImage: "trash", role: .destructive) { deletingPeriod = record }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.wine)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .fittedSheet()
        .alert("Could not save \(store.bleedName)", isPresented: Binding(get: { periodError != nil }, set: { if !$0 { periodError = nil } })) {
            Button("OK") { periodError = nil }
        } message: { Text(periodError ?? "") }
        .confirmationDialog("Delete this entire \(store.bleedName), including its start and end dates?", isPresented: Binding(get: { deletingPeriod != nil }, set: { if !$0 { deletingPeriod = nil } }), titleVisibility: .visible) {
            Button("Delete \(store.bleedName)", role: .destructive) {
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

    // Resolve the period for this date, including an already-ended record
    // so a user can correct its end without first reopening it elsewhere.
    private var periodToEnd: PeriodRecord? {
        store.periodHistory.periodToEnd(on: selectedDate)
    }

    @ViewBuilder
    private var bleedRows: some View {
        if isFutureDate {
            Label("\(store.bleedTitle)s can only be recorded for today or earlier.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(Palette.inkSoft)
        } else if let record = displayedStartPeriod {
            // Changing a date saves straight away; the store rejects overlaps and shows why.
            dateRow("\(store.bleedTitle) started", date: Binding(
                get: { record.start },
                set: { new in performPeriodAction { try store.savePeriod(id: record.id, start: new, end: record.end) } }),
                range: Date.distantPast...(record.end ?? store.today))
            Divider().overlay(Palette.line)
            // Ongoing on: no end date. Off: ends on the day you're looking at, editable below.
            Toggle("Ongoing", isOn: Binding(
                get: { record.end == nil },
                set: { ongoing in
                    performPeriodAction {
                        try store.savePeriod(id: record.id, start: record.start,
                                             end: ongoing ? nil : max(record.start, min(selectedDate, store.today)))
                    }
                }))
                .font(.system(size: 15))
                .frame(minHeight: 44)
            if let end = record.end {
                Divider().overlay(Palette.line)
                dateRow("\(store.bleedTitle) ended", date: Binding(
                    get: { end },
                    set: { new in performPeriodAction { try store.savePeriod(id: record.id, start: record.start, end: new) } }),
                    range: record.start...max(record.start, store.today))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("No \(store.bleedName) logged \(selectedDayLabel).")
                    .font(.system(size: 14)).foregroundStyle(Palette.inkSoft)
                Button {
                    // Before a later bleed it can't run on, so start it as a one-day bleed; the end date is editable right here.
                    let later = store.periodHistory.records.contains { $0.start > selectedDate }
                    performPeriodAction { try store.savePeriod(start: selectedDate, end: later ? selectedDate : nil) }
                } label: {
                    Label("\(store.bleedTitle) started \(selectedDayLabel)", systemImage: "drop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                // Only offer to stretch a bleed that ended in the last few days, not one from months ago.
                if let record = periodToEnd, CycleStore.days(selectedDate, from: record.end ?? record.start) <= 10 {
                    Button("Or end your \(store.fmt(record.start)) \(store.bleedName) here") {
                        performPeriodAction { try store.savePeriod(id: record.id, start: record.start, end: selectedDate) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dateRow(_ title: String, date: Binding<Date>, range: ClosedRange<Date>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DatePicker(title, selection: date, in: range, displayedComponents: .date)
                .labelsHidden()
        }
        .font(.system(size: 15))
        .frame(minHeight: 44)
    }

    /// A quick look at what was logged on the selected day, with a way into the full log.
    @ViewBuilder
    private var dayLogSummary: some View {
        let log = store.log(for: selectedDate)
        HStack {
            Text(log == nil ? "Nothing logged \(selectedDayLabel)" : "Logged \(selectedDayLabel)")
                .font(.system(size: 15, weight: log == nil ? .regular : .semibold))
                .foregroundStyle(log == nil ? Palette.inkSoft : Palette.ink)
            Spacer()
            Button {
                // Opens after this sheet closes; two sheets can't be up at once.
                pendingLogPreview = selectedDate
                showingPeriodControls = false
            } label: {
                HStack(spacing: 4) {
                    Text(log == nil ? "Log this day" : "View log")
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        if let log {
            let tags = log.moods + log.symptoms
            VStack(alignment: .leading, spacing: 4) {
                Text("Flow: \(log.flow) · Pain: \(log.pain == 0 ? "None" : String(log.pain)) · Energy: \(log.energy)/5")
                if !tags.isEmpty {
                    Text(tags.joined(separator: " · ")).lineLimit(2)
                } else if !log.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Note saved")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.inkSoft)
            .padding(.top, 6)
        }
    }

    /// What the selected day is: a recorded period day, a predicted one, or neither.
    private var statusPill: some View {
        let (icon, text, strong): (String, String, Bool) = {
            if let record = displayedStartPeriod {
                let day = CycleStore.days(selectedDate, from: record.start) + 1
                return ("drop.fill", record.end == nil ? "\(store.bleedTitle) day \(day) · ongoing" : "\(store.bleedTitle) day \(day)", true)
            }
            if store.isPredicted(selectedDate) { return ("sparkles", "Predicted \(store.bleedName)", false) }
            return ("circle.dashed", "No \(store.bleedName) recorded", false)
        }()
        return Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(strong ? Color.white : Palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(strong ? Palette.accent : Palette.mist, in: Capsule())
    }


    // MARK: Calendar

    private var monthPicker: some View {
        let monthNames = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
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
                        Text(monthNames[value - 1]).tag(value)
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

    private func showSelectedMonth() {
        guard let date = store.selectedCalendarDate else { return }
        let cal = CycleStore.cal
        let from = cal.dateComponents([.year, .month], from: store.today)
        let to = cal.dateComponents([.year, .month], from: date)
        monthOffset = (to.year! - from.year!) * 12 + to.month! - from.month!
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
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.display(30))
                            .foregroundStyle(Palette.ink)
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
                        let gridBottom = 28 + CGFloat(cellCount / 7) * Self.cellHeight
                        for row in 0...(cellCount / 7) {
                            let y = 28 + CGFloat(row) * Self.cellHeight
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        for column in 0...7 {
                            let x = CGFloat(column) * geometry.size.width / 7
                            path.move(to: CGPoint(x: x, y: 28))
                            path.addLine(to: CGPoint(x: x, y: gridBottom))
                        }
                    }
                    .stroke(Palette.berry.opacity(0.12), lineWidth: 1)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            HStack(spacing: 14) {
                legend(Rectangle().fill(Palette.mist), "\(store.bleedTitle)")
                if store.predictsBleeds {
                    legend(Rectangle().fill(Palette.mist.opacity(0.5)), "Predicted")
                }
                legend(Circle().stroke(Palette.accent, lineWidth: 2), "Today")
                legend(Circle().fill(Palette.accent), "Selected")
            }.font(.caption).foregroundStyle(Palette.inkSoft)
            Text(store.predictsBleeds
                 ? "Predictions are estimates. Your \(store.bleedName) may come a few days earlier or later."
                 : "Sync doesn't predict bleeding on your method. Log any bleeding or spotting to see your pattern.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
    }

    /// Calendar rows are tall so the month reads as the page's main element.
    private static let cellHeight: CGFloat = 64

    private func openLogPreview(on date: Date) {
        store.selectedLogDate = date
        store.showingLogPreview = true
        store.showLog = true
    }

    /// Quick peek for the tapped calendar day. Notes stay private until the full log opens.
    private func calendarLogPreview(_ log: DayLog) -> some View {
        let tags = log.moods + log.symptoms
        let painLabel = log.pain == 0 ? "None" : String(log.pain)
        let hasNote = !log.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Palette.accent)
                Text("Saved log · \(log.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    pendingLogPreview = log.date
                    if showingPeriodControls {
                        showingPeriodControls = false
                    } else {
                        pendingLogPreview = nil
                        openLogPreview(on: log.date)
                    }
                } label: {
                    Label("View full log", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
            Text("Flow: \(log.flow) · Pain: \(painLabel) · Energy: \(log.energy)/5")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSoft)
            if !tags.isEmpty {
                Text(tags.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
            } else if hasNote {
                Text("Note saved")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line))
    }

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
            // First tap selects the day; tapping the selected day again opens its period controls.
            if isSelected {
                showingPeriodControls = true
            } else {
                store.selectedCalendarDate = day
            }
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
                            + (predicted ? ", predicted \(store.bleedName)" : period ? ", \(store.bleedName)" : "")
                            + (periodDay.map { ", \(store.bleedName) day \($0)" } ?? ""))
        .accessibilityHint(isSelected ? "Opens \(store.bleedName) start and end controls for this date" : "Selects this date. Activate again to open \(store.bleedName) start and end controls.")
        .sensoryFeedback(.selection, trigger: isSelected)
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

    /// Cycle length, symptom summary, and period history, swiped through one at a time.
    private var insights: some View {
        let current = insightPage ?? 0
        let summaryHeight = max(insightContentHeights[0] ?? 0, insightContentHeights[1] ?? 0)
        let summaryContentHeight = max(insightContentHeights[10] ?? 0, insightContentHeights[11] ?? 0)
        let visibleHeight = current == 2 ? insightContentHeights[2] : (summaryHeight > 0 ? summaryHeight : nil)
        return VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<Self.insightCount, id: \.self) { page in
                        Group {
                            switch page {
                            case 0:
                                // Cycle length means nothing on hormonal birth control; show what does.
                                switch store.cycleMode {
                                case .natural: lengths
                                case .pack: packSchedule
                                case .steady: bleedingPattern
                                }
                            case 1: symptoms
                            default:
                                logHistory
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            if page < 2 {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: InsightContentHeight.self, value: [page + 10: geometry.size.height])
                                }
                            }
                        }
                        .frame(minHeight: page < 2 ? summaryContentHeight : nil, alignment: .top)
                        .card()
                        .containerRelativeFrame(.horizontal)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: InsightContentHeight.self, value: [page: geometry.size.height])
                            }
                        }
                        .id(page)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .onPreferenceChange(InsightContentHeight.self) { insightContentHeights = $0 }
            .frame(height: visibleHeight, alignment: .top)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $insightPage)
            .scrollIndicators(.hidden)

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

    /// Pill, patch and ring: the pack laid out like a blister pack, with today marked,
    /// and one plain sentence about what's next.
    private var packSchedule: some View {
        let length = BirthControl.packLength
        let active = store.birthControl?.activeDays ?? length
        let day = store.packDay ?? 1
        let packStart = CycleStore.add(store.today, 1 - day)
        let noun = store.birthControl?.method.scheduleNoun.replacingOccurrences(of: "first ", with: "") ?? "pack"
        let inBreak = day > active
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your \(noun)", trailing: store.birthControl?.method.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(inBreak ? "Break day \(day - active) of \(length - active)" : "Active day \(day) of \(active)")
                    .font(.system(size: 17, weight: .semibold))
                Text(inBreak
                     ? "Start your next \(noun) on \(store.fmt(CycleStore.add(packStart, length))). A bleed during the break is normal."
                     : "Your break starts \(store.fmt(CycleStore.add(packStart, active))).")
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(1...length, id: \.self) { d in
                    let isBreak = d > active
                    Circle()
                        .fill(d < day ? (isBreak ? Palette.rose : Palette.blush).opacity(0.35)
                                      : (isBreak ? Palette.rose : Palette.blush))
                        .overlay(Circle().stroke(Palette.ink, lineWidth: d == day ? 2.5 : 0))
                        .frame(width: 22, height: 22)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                packLegend(Palette.blush, "Active")
                packLegend(Palette.rose, "Break")
                HStack(spacing: 5) {
                    Circle().stroke(Palette.ink, lineWidth: 2).frame(width: 9, height: 9)
                    Text("Today")
                }
            }
            .font(.caption).foregroundStyle(Palette.inkSoft)
        }
    }

    private func packLegend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }

    private func scheduleRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    /// Mini-pill, implant, hormonal IUD and shot: no cycle, so list the bleeds the user logged.
    private var bleedingPattern: some View {
        let since = CycleStore.add(store.today, -180)
        let bleeds = store.bleedRecords.filter { $0.start > since && $0.start <= store.today }
        let lengths = bleeds.compactMap { r in r.end.map { CycleStore.days($0, from: r.start) + 1 } }
        let usual = lengths.isEmpty ? nil : lengths.sorted()[lengths.count / 2]
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Bleeding pattern", trailing: "last 6 months")
            if bleeds.isEmpty {
                Text("No bleeding logged in the last 6 months.")
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
            } else {
                Text("\(bleeds.count) bleed\(bleeds.count == 1 ? "" : "s")" + (usual.map { " · usually \($0) day\($0 == 1 ? "" : "s")" } ?? ""))
                    .font(.subheadline.weight(.semibold))
                VStack(spacing: 10) {
                    ForEach(bleeds.prefix(3)) { r in
                        scheduleRow(r.start.formatted(.dateTime.month(.abbreviated).day()),
                                    value: r.end.map { let d = CycleStore.days($0, from: r.start) + 1; return "\(d) day\(d == 1 ? "" : "s")" } ?? "ongoing")
                    }
                }
            }
            if bleeds.count > 3 {
                Button { showingAllLogs = true } label: {
                    HStack(spacing: 6) {
                        Text("View more")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens every saved bleed")
            }
            Text("Bleeding often changes or stops on \(store.birthControl?.method.name.lowercased() ?? "this method"). Log any bleeding or spotting; the pattern is useful to show your doctor.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lengths: some View {
        let cycles = recordedCycles
        let average = cycles.isEmpty ? 0 : Int((Double(cycles.reduce(0) { $0 + $1.days }) / Double(cycles.count)).rounded())
        let maximum = max(cycles.map(\.days).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cycle length", trailing: "saved \(store.bleedName)s")
            if cycles.isEmpty {
                Text("Save at least two \(store.bleedName) start dates to see your first cycle length.")
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
                Text("Cycle length is the number of days between consecutive \(store.bleedName) starts.")
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
                        LabeledContent("\(store.bleedTitle) started", value: cycle.start.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Next \(store.bleedName) started", value: cycle.nextStart.formatted(date: .abbreviated, time: .omitted))
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
                    Text("This cycle is no longer available. Save at least two \(store.bleedName) starts to see cycle details.")
                }
                Section {
                    Text("Calculated from \(store.bleedName) dates saved on this device. Missing starts can make intervals longer.")
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

    // MARK: Period history

    /// The three most recent periods (or bleeds); the rest are a tap away, grouped by month.
    private var logHistory: some View {
        let records = store.periodHistory.records
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "\(store.bleedTitle) history",
                          trailing: "\(records.count) \(store.bleedName)\(records.count == 1 ? "" : "s")")
            if let error = store.periodStorageError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !store.periodsLoaded {
                ProgressView("Loading history…")
            } else if records.isEmpty {
                Text("No \(store.bleedName)s logged yet. Tap a day on the calendar to add one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSoft)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records.prefix(3)) { historyPeriodRow($0) }
                }
            }
            if records.count > 3 {
                Button { showingAllLogs = true } label: {
                    HStack(spacing: 6) {
                        Text("View more")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens every saved \(store.bleedName)")
            }
        }
    }

    /// Every period, newest first, under a header for the month it started in.
    /// Search matches the month or dates, or anything logged during the period.
    private var allPeriods: some View {
        let query = periodSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = store.periodHistory.records.filter { periodMatches($0, query) }
        let byMonth = Dictionary(grouping: matches) { record in
            Calendar.current.dateInterval(of: .month, for: record.start)?.start ?? record.start
        }
        return LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.inkFaint)
                TextField("Search months, symptoms, moods or notes", text: $periodSearch)
                    .font(.system(size: 13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !periodSearch.isEmpty {
                    Button { periodSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)

            if matches.isEmpty {
                Text(query.isEmpty ? "No \(store.bleedName)s logged yet." : "No \(store.bleedName)s match \"\(query)\".")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, 16)
            }
            ForEach(byMonth.keys.sorted(by: >), id: \.self) { month in
                Section {
                    ForEach(byMonth[month] ?? []) { historyPeriodRow($0) }
                } header: {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16).padding(.bottom, 4)
                        .background(Palette.bg)
                }
            }
        }
    }

    private func periodMatches(_ record: PeriodRecord, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let last = record.end ?? store.today
        let dates = [record.start.formatted(.dateTime.month(.wide).year()), store.fmt(record.start), store.fmt(last)]
        let logged = store.logs
            .filter { CycleStore.cal.startOfDay(for: $0.date) >= CycleStore.cal.startOfDay(for: record.start)
                && CycleStore.cal.startOfDay(for: $0.date) <= CycleStore.cal.startOfDay(for: last) }
            .flatMap { $0.symptoms + $0.moods + [$0.flow == "None" ? "" : $0.flow, $0.note] }
        return (dates + logged).contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func historyPeriodRow(_ record: PeriodRecord) -> some View {
        Button {
            fromHistory {
                store.selectedCalendarDate = record.start
                showingPeriodControls = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.bleedTitle)").font(.system(size: 14, weight: .semibold))
                    Text(store.fmt(record.start) + " – " + (record.end.map { store.fmt($0) } ?? "Ongoing"))
                        .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
            }
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this \(store.bleedName)'s saved dates and controls")
    }

    /// Rows in the View more sheet open other sheets, so close it first and run the action after.
    private func fromHistory(_ action: @escaping () -> Void) {
        if showingAllLogs {
            afterAllLogs = action
            showingAllLogs = false
        } else {
            action()
        }
    }
}
