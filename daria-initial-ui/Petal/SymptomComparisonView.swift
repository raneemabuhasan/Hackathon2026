import SwiftUI

@MainActor
struct SymptomComparisonView: View {
    @Environment(CycleStore.self) private var store
    @State private var first: Date?
    @State private var second: Date?

    private var cycles: [ComparedCycle] { Array(store.comparisonCycles.reversed()) }
    private var comparison: CycleComparison? {
        guard cycles.count >= 2 else { return nil }
        let a = cycles.first { $0.start == first } ?? cycles[0]
        let b = cycles.first { $0.start == second } ?? cycles[1]
        return SymptomComparisonEngine.compare(a, b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Compare cycles")
            Text("Choose two cycles to see what you logged in each one.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if !store.logsLoaded {
                ProgressView("Loading symptom history")
            } else if let error = store.logsError {
                Text("We couldn't load your symptom history. Please try again when you're connected.")
                    .foregroundStyle(.red)
                DisclosureGroup("Error details") { Text(error).font(.caption) }
            } else if cycles.count < 2 {
                Text("Add a little more history")
                    .font(.headline)
                Text("Mark the start of at least two periods on the calendar above. Then you can compare what you logged in each cycle.")
            } else {
                selector("Choose a cycle", selection: $first, fallback: cycles[0].start)
                selector("Compare with", selection: $second, fallback: cycles[1].start)
                if let result = comparison {
                    if result.later.isOngoing {
                        Label("The cycle starting \(label(result.later)) is still in progress.", systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                        Text("No next period start has been recorded. This cycle's totals include entries up to today, even if bleeding has ended.")
                            .font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    Divider()
                    Text("Days you logged each symptom").font(.headline)
                    Text("Each day counts once, even if you logged a symptom more than once. More logged days doesn't necessarily mean worse symptoms.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    if result.observations.isEmpty {
                        Text("No symptoms logged for these cycles yet.")
                        Text("Use + to add an entry. A day without an entry doesn't tell us whether you had symptoms.")
                            .font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    ForEach(result.observations) { observation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(observation.symptom).font(.headline)
                            cycleValues(result, earlier: dayCount(observation.earlierDays),
                                        later: dayCount(observation.laterDays))
                            Text(observation.cyclesReported == 2
                                 ? "Logged in both cycles."
                                 : "Logged in one cycle. No entries for this symptom in the other.")
                                .font(.caption).foregroundStyle(Palette.inkSoft)
                            DisclosureGroup(entryTitle(observation.evidence.count)) {
                                ForEach(observation.evidence) { entry in evidence(entry) }
                            }
                        }.padding(.vertical, 6)
                        Divider()
                    }
                    Text("Highest daily pain logged").font(.headline)
                    Text("Your highest overall pain rating in each cycle, on a scale of 1–10. This isn't a separate rating for each symptom.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    cycleValues(result, earlier: rating(result.earlierPeakPain), later: rating(result.laterPeakPain))
                    DisclosureGroup("Why aren't zero ratings included?") {
                        Text("A saved 0 can mean either no pain or no rating entered. To avoid guessing, this comparison only includes ratings from 1 to 10.")
                            .font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    DisclosureGroup("View all entries for these cycles (\(result.earlier.logs.count + result.later.logs.count))") {
                        ForEach(result.earlier.logs + result.later.logs) { entry in evidence(entry) }
                    }
                    Text("No entry means no information — it doesn't mean you had no symptoms.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                } else {
                    Label("You've selected the same cycle twice. Choose a different date to compare.", systemImage: "info.circle")
                }
            }
        }.font(.system(size: 13)).card()
    }

    private func rating(_ value: Int?) -> String { value.map { "\($0) out of 10" } ?? "No rating above 0 logged" }
    private func dayCount(_ count: Int) -> String {
        count == 0 ? "No entries" : "\(count) \(count == 1 ? "day" : "days") logged"
    }
    private func entryTitle(_ count: Int) -> String {
        "View \(count) \(count == 1 ? "entry" : "entries")"
    }
    private func cycleValues(_ result: CycleComparison, earlier: String, later: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                cycleValue(result.earlier, title: "Earlier cycle", value: earlier)
                cycleValue(result.later, title: "Later cycle", value: later)
            }
            VStack(alignment: .leading, spacing: 10) {
                cycleValue(result.earlier, title: "Earlier cycle", value: earlier)
                cycleValue(result.later, title: "Later cycle", value: later)
            }
        }
    }
    private func cycleValue(_ cycle: ComparedCycle, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Palette.inkSoft)
            Text("Started \(label(cycle))").font(.caption.weight(.medium))
            Text(value).font(.subheadline.bold())
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
    private func label(_ cycle: ComparedCycle) -> String {
        cycle.start.formatted(date: .abbreviated, time: .omitted)
    }
    private func selector(_ title: String, selection: Binding<Date?>, fallback: Date) -> some View {
        Picker(title, selection: Binding<Date>(get: {
            cycles.contains { $0.start == selection.wrappedValue } ? (selection.wrappedValue ?? fallback) : fallback
        }, set: { selection.wrappedValue = $0 })) {
            ForEach(cycles) { cycle in Text("Started \(label(cycle))").tag(cycle.start) }
        }.pickerStyle(.menu)
    }
    private func evidence(_ entry: ComparisonEntry) -> some View {
        Button {
            store.selectedLogDate = entry.date
            store.showLog = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).bold()
                Text(entry.symptoms.isEmpty ? "No symptoms recorded" : entry.symptoms.joined(separator: ", "))
                Text("Daily pain: \(rating(entry.pain))")
                if !entry.note.isEmpty { Text(entry.note) }
                Label("View or edit entry", systemImage: "pencil").foregroundStyle(Palette.accent)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
}
