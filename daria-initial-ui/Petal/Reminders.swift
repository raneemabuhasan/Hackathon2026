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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    DisplayTitle(before: original == nil ? "New " : "Edit ", accent: "Reminder", size: 32)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                Text("A little nudge, on your schedule.")
                    .font(.system(size: 16)).foregroundStyle(Palette.inkSoft)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Remind me to…").font(.cardSubheading)
                    TextField("Reminder title", text: $title, prompt: Text(""))
                        .font(.system(size: 15))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if original?.greets == true {
                        Text("Starts with a greeting for the time of day and your name.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Text("When").font(.cardSubheading)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                        scheduleTile("Every day", icon: "sun.max", selected: kind == .daily && !selectedDays) {
                            kind = .daily; selectedDays = false
                        }
                        scheduleTile("Selected days", icon: "calendar.badge.clock", selected: kind == .daily && selectedDays) {
                            kind = .daily; selectedDays = true
                        }
                        scheduleTile("Once", icon: "calendar", selected: kind == .once) { kind = .once; selectedDays = false }
                        scheduleTile("Before period", icon: "drop", selected: kind == .beforePeriod) { kind = .beforePeriod; selectedDays = false }
                    }
                    // Preserve pack/patch/ring repeat intervals supported by the existing scheduler.
                    scheduleTile("Every few weeks", icon: "repeat", selected: kind == .everyWeeks) {
                        kind = .everyWeeks; selectedDays = false
                    }

                    switch kind {
                    case .daily:
                        if selectedDays {
                            Text("Repeat on").font(.cardSubheading)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                    scheduleTile([1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"][day]!,
                                                 selected: weekdays.contains(day)) {
                                        if !weekdays.insert(day).inserted { weekdays.remove(day) }
                                    }
                                }
                            }
                            Text("Repeats every week on the days you select.")
                                .font(.caption).foregroundStyle(Palette.inkSoft)
                        }
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
                .card()

                Button(action: save) {
                    Text("Save reminder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.surface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(trimmedTitle.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty || (kind == .daily && selectedDays && weekdays.isEmpty))

                if let original {
                    Button { confirmingDelete = true } label: {
                        Label("Delete reminder", systemImage: "trash")
                            .font(.system(size: 14, weight: .semibold))
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
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .background(Palette.bg.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: kind)
    }

    private func scheduleTile(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 18)) }
                Text(title).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.leading)
                if icon != nil && selected { Spacer(minLength: 0); Image(systemName: "checkmark.circle.fill") }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(10)
            .background(selected ? Palette.blushPink : Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 1.5 : 1))
            .foregroundStyle(selected ? Palette.accent : Palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
