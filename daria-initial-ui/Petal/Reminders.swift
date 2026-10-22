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
        }
    }

    func fireDate(windowStart: Date) -> Date? {
        guard let day = day(windowStart: windowStart) else { return nil }
        return CycleStore.cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    func detail(windowStart: Date) -> String {
        let time = Self.time(hour, minute)
        switch kind {
        case .daily:
            return "Every day · \(time)"
        case .once:
            guard let fire = fireDate(windowStart: windowStart) else { return "Once · \(time)" }
            return fire < .now ? "Done · \(fire.formatted(.dateTime.month(.abbreviated).day()))" : "\(fire.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
        case .beforePeriod:
            let days = daysBefore ?? 2
            let when = fireDate(windowStart: windowStart).map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
            return "\(days) day\(days == 1 ? "" : "s") before your period · \(when), \(time)"
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
    static func sync(_ reminders: [Reminder], windowStart: Date, name: String) {
        generation += 1
        let currentGeneration = generation
        let requests = reminders.filter(\.on).compactMap { request(for: $0, windowStart: windowStart, name: name) }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            Task { @MainActor in
                guard generation == currentGeneration else { return }
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
                requests.forEach { center.add($0) }
            }
        }
    }

    private static func request(for reminder: Reminder, windowStart: Date, name: String) -> UNNotificationRequest? {
        let trigger: UNCalendarNotificationTrigger
        if reminder.kind == .daily {
            trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: reminder.hour, minute: reminder.minute), repeats: true)
        } else {
            guard let fire = reminder.fireDate(windowStart: windowStart), fire > .now else { return nil }
            let parts = CycleStore.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        // iOS banners don't show the app name, so it goes in the title and the reminder underneath.
        let content = UNMutableNotificationContent()
        content.title = appName
        if reminder.kind == .beforePeriod {
            let days = reminder.daysBefore ?? 2
            content.subtitle = reminder.title
            content.body = "Your period may start in about \(days) day\(days == 1 ? "" : "s")."
        } else {
            content.body = reminder.text(name: name)
        }
        content.sound = .default
        return UNNotificationRequest(identifier: prefix + reminder.id, content: content, trigger: trigger)
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
    @State private var confirmingDelete = false

    init(reminder: Reminder?) {
        original = reminder
        let r = reminder ?? Reminder(title: "", kind: .daily, hour: 9, minute: 0)
        _title = State(initialValue: r.title)
        _kind = State(initialValue: r.kind)
        _time = State(initialValue: CycleStore.cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: .now) ?? .now)
        _date = State(initialValue: r.date ?? CycleStore.add(.now, 1))
        _daysBefore = State(initialValue: r.daysBefore ?? 2)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Eyebrow(text: original == nil ? "New reminder" : "Edit reminder")
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Remind me to…").font(.system(size: 15, weight: .semibold))
                    TextField("e.g. Take my iron tablet", text: $title)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Text("When").font(.system(size: 15, weight: .semibold))
                    Picker("Schedule", selection: $kind) {
                        ForEach(Reminder.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch kind {
                    case .daily:
                        EmptyView()
                    case .once:
                        DatePicker("Date", selection: $date, in: Date.now..., displayedComponents: .date)
                    case .beforePeriod:
                        Stepper("\(daysBefore) day\(daysBefore == 1 ? "" : "s") before", value: $daysBefore, in: 1...7)
                        Text("Moves with your predicted window. Next: \(CycleStore.add(store.windowStart, -daysBefore).formatted(.dateTime.month(.abbreviated).day())).")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                .font(.system(size: 14))
                .card()

                Button(action: save) {
                    Text("Save reminder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent.opacity(trimmedTitle.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty)

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
        .animation(.easeOut(duration: 0.2), value: kind)
    }

    private func save() {
        let parts = CycleStore.cal.dateComponents([.hour, .minute], from: time)
        var r = original ?? Reminder(title: "", kind: kind, hour: 9, minute: 0)
        r.title = trimmedTitle
        r.kind = kind
        r.hour = parts.hour ?? 9
        r.minute = parts.minute ?? 0
        r.date = kind == .once ? CycleStore.cal.startOfDay(for: date) : nil
        r.daysBefore = kind == .beforePeriod ? daysBefore : nil
        r.on = true
        store.saveReminder(r)
        dismiss()
    }
}
