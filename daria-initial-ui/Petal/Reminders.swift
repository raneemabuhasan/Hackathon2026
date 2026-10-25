import SwiftUI
import UserNotifications

extension Reminder {
    static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// What the notification and the reminders list show.
    func text(name: String) -> String {
        guard greets == true else { return title }
        return "\(Self.greeting(hour: hour))\(name.isEmpty ? "" : ", \(name)"). \(title)"
    }

    /// Short name for the settings list; the built-in reminders get a label, custom ones keep their title.
    var listName: String {
        if greets == true { return "Daily check-in" }
        switch title {
        case "Period may start soon": return "Period reminder"
        case "Bleed may start soon": return "Bleed reminder"
        default: return title
        }
    }

    /// The next day this fires on (ignoring the time), or nil if it's a past one-off.
    func day(windowStart: Date) -> Date? {
        switch kind {
        case .daily: return nil
        case .once: return date
        case .beforePeriod: return CycleStore.add(windowStart, -(daysBefore ?? 2))
        case .everyWeeks: return upcomingDays(count: 1).first
        }
    }

    /// The next repeats of an `.everyWeeks` reminder, today included until its time passes.
    func upcomingDays(count: Int) -> [Date] {
        guard kind == .everyWeeks, let anchor = date else { return [] }
        let step = 7 * max(1, weeks ?? 1)
        let today = CycleStore.cal.startOfDay(for: .now)
        var n = max(0, Int((Double(CycleStore.days(today, from: anchor)) / Double(step)).rounded(.up)))
        var days: [Date] = []
        while days.count < count {
            let day = CycleStore.add(anchor, n * step)
            if let fire = CycleStore.cal.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > .now { days.append(day) }
            n += 1
        }
        return days
    }

    func fireDate(windowStart: Date) -> Date? {
        guard let day = day(windowStart: windowStart) else { return nil }
        return CycleStore.cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    func detail(windowStart: Date) -> String {
        let time = Self.time(hour, minute)
        switch kind {
        case .daily:
            if let weekdays = repeatWeekdays {
                let labels = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
                return "Every \(weekdays.compactMap { labels[$0] }.joined(separator: ", ")) · \(time)"
            }
            return "Every day · \(time)"
        case .once:
            guard let fire = fireDate(windowStart: windowStart) else { return "Once · \(time)" }
            return fire < .now ? "Done · \(fire.formatted(.dateTime.month(.abbreviated).day()))" : "\(fire.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
        case .beforePeriod:
            let days = daysBefore ?? 2
            let when = fireDate(windowStart: windowStart).map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
            return "\(days) day\(days == 1 ? "" : "s") before your period · \(when), \(time)"
        case .everyWeeks:
            let every = weeks ?? 1
            let next = fireDate(windowStart: windowStart).map { " · next \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
            return "Every \(every == 1 ? "week" : "\(every) weeks")\(next), \(time)"
        }
    }

    static func time(_ hour: Int, _ minute: Int) -> String {
        let date = CycleStore.cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Mirrors the enabled reminders into local iOS notifications. Works without a paid developer account.
@MainActor
enum ReminderNotifications {
    private static var generation = 0
    private static let prefix = "reminder-"
    private static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Sync"

    /// iOS hides notifications while the app is open unless a delegate opts in.
    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
            completion([.banner, .list, .sound])
        }
    }
    private static let presenter = ForegroundPresenter()

    /// Call once at launch so reminders still show as banners when Petal is in the foreground.
    static func showWhileOpen() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { print("Notification permission failed:", error) }
        }
    }

    /// Replaces every pending Petal reminder with the current set. Call whenever reminders or predictions change.
    /// `bleed` words the period heads-up for someone on hormonal birth control.
    static func sync(_ reminders: [Reminder], windowStart: Date, name: String, bleed: Bool) {
        generation += 1
        let currentGeneration = generation
        let requests = reminders.filter(\.on).flatMap { requests(for: $0, windowStart: windowStart, name: name, bleed: bleed) }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            Task { @MainActor in
                guard generation == currentGeneration else { return }
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
                requests.forEach { center.add($0) }
            }
        }
    }

    /// iOS can't repeat every few weeks, so `.everyWeeks` queues its next few dates; each sync tops them up.
    private static func requests(for reminder: Reminder, windowStart: Date, name: String, bleed: Bool) -> [UNNotificationRequest] {
        if reminder.kind == .everyWeeks {
            return reminder.upcomingDays(count: 6).enumerated().compactMap { i, day in
                let parts = CycleStore.cal.dateComponents([.year, .month, .day], from: day)
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: reminder.hour, minute: reminder.minute),
                    repeats: false)
                return request(for: reminder, id: "\(prefix)\(reminder.id)-\(i)", trigger: trigger, name: name, bleed: bleed)
            }
        }
        if reminder.kind == .daily {
            return reminder.dailyNotificationComponents.map { components in
                let suffix = components.weekday.map { "-weekday-\($0)" } ?? ""
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                return request(for: reminder, id: prefix + reminder.id + suffix, trigger: trigger, name: name, bleed: bleed)
            }
        }
        guard let fire = reminder.fireDate(windowStart: windowStart), fire > .now else { return [] }
        let parts = CycleStore.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return [request(for: reminder, id: prefix + reminder.id, trigger: trigger, name: name, bleed: bleed)]
    }

    private static func request(for reminder: Reminder, id: String, trigger: UNCalendarNotificationTrigger,
                                name: String, bleed: Bool) -> UNNotificationRequest {
        // iOS banners don't show the app name, so it goes in the title and the reminder underneath.
        let content = UNMutableNotificationContent()
        content.title = appName
        if reminder.kind == .beforePeriod {
            let days = reminder.daysBefore ?? 2
            content.subtitle = reminder.title
            content.body = "Your \(bleed ? "next bleed" : "period") may start in about \(days) day\(days == 1 ? "" : "s")."
        } else {
            content.body = reminder.text(name: name)
        }
        content.sound = .default
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

/// Create or edit a reminder.
@MainActor
struct ReminderEditor: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Reminder?
    @State private var title: String
    @State private var kind: Reminder.Kind
    @State private var time: Date
    @State private var date: Date
    @State private var daysBefore: Int
    @State private var weeks: Int
    @State private var selectedDays = false
    @State private var weekdays: Set<Int> = []
    @State private var confirmingDelete = false

    init(reminder: Reminder?) {
        original = reminder
        let r = reminder ?? Reminder(title: "", kind: .daily, hour: 9, minute: 0)
        _title = State(initialValue: r.title)
        _kind = State(initialValue: r.kind)
        _time = State(initialValue: CycleStore.cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: .now) ?? .now)
        _date = State(initialValue: r.date ?? CycleStore.add(.now, 1))
        _daysBefore = State(initialValue: r.daysBefore ?? 2)
        _weeks = State(initialValue: r.weeks ?? 1)
        _selectedDays = State(initialValue: r.kind == .daily && r.weekdays != nil)
        _weekdays = State(initialValue: Set(r.repeatWeekdays ?? []))
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The schedule tiles; "Selected days" is a daily reminder with weekdays.
    private enum Schedule: String, CaseIterable, Identifiable {
        case daily = "Every day", selectedDays = "Selected days", once = "Once"
        case beforePeriod = "Before period", everyWeeks = "Every few weeks"
        var id: Self { self }
        var icon: String {
            switch self {
            case .daily: "sun.max"
            case .selectedDays: "calendar.badge.clock"
            case .once: "calendar"
            case .beforePeriod: "drop"
            case .everyWeeks: "repeat"
            }
        }
    }

    private var schedule: Binding<Schedule> {
        Binding {
            switch kind {
            case .daily: selectedDays ? .selectedDays : .daily
            case .once: .once
            case .beforePeriod: .beforePeriod
            case .everyWeeks: .everyWeeks
            }
        } set: { picked in
            selectedDays = picked == .selectedDays
            switch picked {
            case .daily, .selectedDays: kind = .daily
            case .once: kind = .once
            case .beforePeriod: kind = .beforePeriod
            case .everyWeeks: kind = .everyWeeks
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    DisplayTitle(before: original == nil ? "New " : "Edit ", accent: "reminder", size: 26)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("Remind me to…")
                    TextField("Reminder title", text: $title, prompt: Text("e.g. Take a walk"))
                        .font(.system(size: 15))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if original?.greets == true {
                        Text("Starts with a greeting for the time of day and your name.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                    }
                }
                .compactCard()

                VStack(alignment: .leading, spacing: 10) {
                    label("When")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Schedule.allCases) { option in
                            scheduleTile(option.rawValue, icon: option.icon, selected: schedule.wrappedValue == option) {
                                schedule.wrappedValue = option
                            }
                        }
                    }

                    Group {
                        switch kind {
                        case .daily:
                            if selectedDays { weekdayPicker.padding(.top, 4) }
                        case .once:
                            DatePicker("Date", selection: $date, in: Date.now..., displayedComponents: .date)
                        case .beforePeriod:
                            Stepper("\(daysBefore) day\(daysBefore == 1 ? "" : "s") before", value: $daysBefore, in: 1...7)
                            Text("Moves with your predicted window. Next: \(CycleStore.add(store.windowStart, -daysBefore).formatted(.dateTime.month(.abbreviated).day())).")
                                .font(.caption).foregroundStyle(Palette.inkFaint)
                        case .everyWeeks:
                            DatePicker("Starting", selection: $date, displayedComponents: .date)
                            Stepper("Every \(weeks == 1 ? "week" : "\(weeks) weeks")", value: $weeks, in: 1...4)
                        }
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    .font(.system(size: 14))
                }
                .compactCard()

                Button(action: save) {
                    Text("Save reminder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.surface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.accent.opacity(canSave ? 1 : 0.4), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                if let original {
                    Button { confirmingDelete = true } label: {
                        Label("Delete reminder", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete \"\(original.title)\"?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            store.deleteReminder(original)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("You won't get this reminder any more.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .background(Palette.bg.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: kind)
        .animation(.easeOut(duration: 0.2), value: selectedDays)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !(kind == .daily && selectedDays && weekdays.isEmpty)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
    }

    private func scheduleTile(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 8)
            .background(selected ? Palette.blushPink : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 1.5 : 1))
            .foregroundStyle(selected ? Palette.accent : Palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// One round button per weekday, Monday first.
    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                let on = weekdays.contains(day)
                Button {
                    if !weekdays.insert(day).inserted { weekdays.remove(day) }
                } label: {
                    Text(CycleStore.cal.veryShortWeekdaySymbols[day - 1])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(on ? Palette.surface : Palette.ink)
                        .background(on ? Palette.accent : Palette.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CycleStore.cal.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func save() {
        let parts = CycleStore.cal.dateComponents([.hour, .minute], from: time)
        var r = original ?? Reminder(title: "", kind: kind, hour: 9, minute: 0)
        r.title = trimmedTitle
        r.kind = kind
        r.hour = parts.hour ?? 9
        r.minute = parts.minute ?? 0
        r.date = kind == .once || kind == .everyWeeks ? CycleStore.cal.startOfDay(for: date) : nil
        r.daysBefore = kind == .beforePeriod ? daysBefore : nil
        r.weeks = kind == .everyWeeks ? weeks : nil
        r.weekdays = kind == .daily && selectedDays ? [2, 3, 4, 5, 6, 7, 1].filter { weekdays.contains($0) } : nil
        r.on = true
        store.saveReminder(r)
        dismiss()
    }
}

private extension View {
    /// A tighter version of `card()` for the reminder editor.
    func compactCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Palette.berry.opacity(0.07), radius: 12, y: 5)
    }
}
