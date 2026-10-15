import SwiftUI

struct SymptomComparisonView: View {
    @Environment(CycleStore.self) private var store
    @State private var first: Date?
    @State private var second: Date?
    @State private var editing: DayLog?

    private var cycles: [ComparedCycle] { Array(store.comparisonCycles.reversed()) }
    private var comparison: CycleComparison? {
        guard cycles.count >= 2 else { return nil }
        let a = cycles.first(where: { $0.start == first }) ?? cycles[0]
        let b = cycles.first(where: { $0.start == second }) ?? cycles[1]
        return SymptomComparisonEngine.compare(a, b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Compare cycles")
            Text("Counts describe recorded days; missing entries do not mean symptoms were absent.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if cycles.count < 2 {
                Text("Add at least two period start dates to compare cycles.")
            } else {
                selector("First cycle", selection: $first, fallback: cycles[0].start)
                selector("Second cycle", selection: $second, fallback: cycles[1].start)
                if let result = comparison {
                    if result.later.isOngoing {
                        Text("The later cycle is ongoing. Its counts are only up to today.").font(.caption)
                    }
                    Text("Earlier / Later").font(.caption).foregroundStyle(Palette.inkSoft)
                    if result.observations.isEmpty {
                        Text("No symptoms recorded in these cycles. There is not enough evidence to identify a pattern.")
                    }
                    ForEach(result.observations) { observation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(observation.symptom).font(.headline)
                            Text("Recorded days: \(observation.earlierDays) / \(observation.laterDays)")
                            Text(observation.cyclesReported == 2
                                 ? "Reported in both selected cycles."
                                 : "Reported in one selected cycle; the other has no entry for this symptom.")
                                .font(.caption).foregroundStyle(Palette.inkSoft)
                            DisclosureGroup("Supporting entries (\(observation.evidence.count))") {
                                ForEach(observation.evidence) { entry in
                                    evidence(entry)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                    Text("Highest reported overall daily pain (0–10)").font(.subheadline.bold())
                    Text("Earlier: \(rating(result.earlierPeakPain)) · Later: \(rating(result.laterPeakPain))")
                    Text("This is a daily pain rating, not a severity rating for each symptom. More recorded days do not establish worsening symptoms.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                    DisclosureGroup("All selected entries / pain evidence") {
                        ForEach(result.earlier.logs + result.later.logs) { entry in evidence(entry) }
                    }
                } else {
                    Text("Choose two different cycles.")
                }
            }
        }
        .font(.system(size: 13))
        .card()
        .sheet(item: $editing) { entry in
            ComparisonEntryEditor(entry: entry).environment(store)
        }
    }

    private func rating(_ value: Int?) -> String { value.map { "\($0)/10" } ?? "Not reported" }
    private func label(_ cycle: ComparedCycle) -> String {
        cycle.start.formatted(date: .abbreviated, time: .omitted) + (cycle.isOngoing ? " (ongoing)" : "")
    }
    private func selector(_ title: String, selection: Binding<Date?>, fallback: Date) -> some View {
        Picker(title, selection: Binding<Date>(get: { cycles.contains { $0.start == selection.wrappedValue } ? (selection.wrappedValue ?? fallback) : fallback },
                                              set: { selection.wrappedValue = $0 })) {
            ForEach(cycles) { cycle in Text(label(cycle)).tag(cycle.start) }
        }
        .pickerStyle(.menu)
    }
    private func evidence(_ entry: DayLog) -> some View {
        Button { editing = entry } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).bold()
                Text(entry.symptoms.isEmpty ? "No symptoms recorded" : entry.symptoms.joined(separator: ", "))
                Text("Overall daily pain: \(rating(entry.pain))")
                if !entry.note.isEmpty { Text(entry.note) }
                Text("Review / edit entry").foregroundStyle(Palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
}

private struct ComparisonEntryEditor: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var entry: DayLog
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.storageError { Text(error) }
                Section("Recorded date") { Text(entry.date.formatted(date: .complete, time: .omitted)) }
                Section("Symptoms") {
                    ForEach(Array(Set(CycleStore.symptomOptions + entry.symptoms)).sorted(), id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { entry.symptoms.contains(name) }, set: { selected in
                            entry.symptoms.removeAll { $0 == name }
                            if selected { entry.symptoms.append(name) }
                        }))
                    }
                }
                Section("Overall daily pain") {
                    Toggle("Include a rating", isOn: Binding(get: { entry.pain != nil },
                        set: { entry.pain = $0 ? 0 : nil }))
                    if entry.pain != nil {
                        Stepper("\(entry.pain ?? 0)/10", value: Binding(get: { entry.pain ?? 0 },
                            set: { entry.pain = $0 }), in: 0...10)
                    }
                }
                Section("Note") { TextField("Note", text: $entry.note, axis: .vertical) }
                Button("Delete entry", role: .destructive) { confirmingDelete = true }
            }
            .navigationTitle("Review entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.updateLog(entry) { dismiss() } }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) { if store.deleteLog(id: entry.id) { dismiss() } }
            }
        }
    }
}
