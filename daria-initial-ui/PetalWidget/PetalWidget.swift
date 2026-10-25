import WidgetKit
import SwiftUI

@main
struct PetalWidgets: WidgetBundle {
    var body: some Widget { LogShortcutWidget() }
}

/// Home screen shortcut to today's log. It deliberately shows no cycle or health details,
/// so it is safe on a screen other people can see.
struct LogShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LogShortcut", provider: LogShortcutProvider()) { _ in
            LogShortcutEntryView()
        }
        .configurationDisplayName("Quick log")
        .description("Opens Sync to log today. Shows no cycle details.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The widget never changes, so one entry is enough.
struct LogShortcutProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

/// Reads the size the user picked and hands it to the layout.
struct LogShortcutEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LogShortcutView(family: family)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Palette.cream, Palette.surface2], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(DeepLink.log.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Log today in Sync")
    }
}

struct LogShortcutView: View {
    let family: WidgetFamily

    var body: some View {
        VStack(spacing: spacing) {
            FigPlus(height: figHeight)
            Text("Log \(Text("today").italic().foregroundStyle(Palette.accent))")
                .font(.system(size: titleSize, weight: .medium, design: .serif))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var figHeight: CGFloat {
        switch family {
        case .systemMedium: 96
        case .systemLarge: 210
        default: 92
        }
    }

    private var titleSize: CGFloat {
        switch family {
        case .systemMedium: 26
        case .systemLarge: 38
        default: 22
        }
    }

    private var spacing: CGFloat { family == .systemLarge ? 18 : 6 }
}

/// The fig "S" from the Sync logo with a + in its flesh.
struct FigPlus: View {
    let height: CGFloat

    var body: some View {
        Image("SyncFig")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .overlay {
                GeometryReader { geo in
                    Image(systemName: "plus")
                        .font(.system(size: height * 0.2, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Palette.wine.opacity(0.25), radius: 1, y: 1)
                        // Centre of the fig's flesh, measured from the artwork.
                        .position(x: geo.size.width * 0.443, y: geo.size.height * 0.687)
                }
            }
    }
}

#Preview(as: .systemSmall) {
    LogShortcutWidget()
} timeline: {
    LogShortcutProvider.Entry(date: .now)
}

#Preview(as: .systemMedium) {
    LogShortcutWidget()
} timeline: {
    LogShortcutProvider.Entry(date: .now)
}

#Preview(as: .systemLarge) {
    LogShortcutWidget()
} timeline: {
    LogShortcutProvider.Entry(date: .now)
}
