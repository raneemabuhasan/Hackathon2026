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
            Text("Uses saved period starts. Counts are recorded days, not symptom episodes.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if !store.logsLoaded {
                ProgressView("Loading symptom history")
            } else if let error = store.logsError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if cycles.count < 2 {
                Text("Record at least two period starts on the calendar to compare.")
            } else {
                selector("First cycle", selection: $first, fallback: cycles[0].start)
                selector("Second cycle", selection: $second, fallback: cycles[1].start)
                if let result = comparison {
                    Text("Earlier: \(label(result.earlier)) / Later: \(label(result.later))").font(.caption)
                    if result.later.isOngoing {
                        Text("The later cycle has no following start recorded. Counts are up to today.").font(.caption)
                    }
                    Text("Missing entries do not mean symptoms were absent. More recorded days do not establish worsening symptoms.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    if result.observations.isEmpty { Text("No symptoms recorded in the selected cycles.") }
                    ForEach(result.observations) { observation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(observation.symptom).font(.headline)
                            Text("Recorded days: \(observation.earlierDays) / \(observation.laterDays)")
                            Text("Reported in \(observation.cyclesReported) of the 2 selected cycles.")
                                .font(.caption).foregroundStyle(Palette.inkSoft)
                            DisclosureGroup("Supporting entries (\(observation.evidence.count))") {
                                ForEach(observation.evidence) { entry in evidence(entry) }
                            }
                        }.padding(.vertical, 6)
                        Divider()
                    }
                    Text("Highest positive overall daily pain rating").font(.subheadline.bold())
                    Text("Earlier: \(rating(result.earlierPeakPain)) / Later: \(rating(result.laterPeakPain))")
                    Text("Older logs use 0 for both the default and a zero rating, so zeros are excluded. This is overall daily pain, not severity for each symptom.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    DisclosureGroup("All selected entries / pain evidence") {
                        ForEach(result.earlier.logs + result.later.logs) { entry in evidence(entry) }
                    }
                } else { Text("Choose two different cycles.") }
            }
        }.font(.system(size: 13)).card()
    }

    private func rating(_ value: Int?) -> String { value.map { "\($0)/10" } ?? "No positive rating recorded" }
    private func label(_ cycle: ComparedCycle) -> String {
        cycle.start.formatted(date: .abbreviated, time: .omitted)
    }
    private func selector(_ title: String, selection: Binding<Date?>, fallback: Date) -> some View {
        Picker(title, selection: Binding<Date>(get: {
            cycles.contains { $0.start == selection.wrappedValue } ? (selection.wrappedValue ?? fallback) : fallback
        }, set: { selection.wrappedValue = $0 })) {
            ForEach(cycles) { cycle in Text(label(cycle)).tag(cycle.start) }
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
                Text("Overall daily pain: \(rating(entry.pain))")
                if !entry.note.isEmpty { Text(entry.note) }
                Text("Review / edit saved entry").foregroundStyle(Palette.accent)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
}
