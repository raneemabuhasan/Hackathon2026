import SwiftUI

struct PeriodHistoryView: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    @State private var hasEnd = false
    @State private var original: Date?
    @State private var deleting: Date?

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.storageError { Text(error) }
                Section(original == nil ? "Record a period" : "Edit period") {
                    DatePicker("Start", selection: $start, in: ...Date(), displayedComponents: .date)
                    Toggle("Period has ended", isOn: $hasEnd)
                    if hasEnd { DatePicker("End", selection: $end, in: ...Date(), displayedComponents: .date) }
                    Button("Save period dates") {
                        if store.savePeriod(start: start, end: hasEnd ? end : nil, replacing: original) {
                            original = nil; start = .now; end = .now; hasEnd = false
                        }
                    }.disabled(!store.storageReady)
                    if original != nil { Button("Cancel editing") { original = nil; start = .now; hasEnd = false } }
                }
                Section("Recorded periods") {
                    ForEach(store.starts, id: \.self) { date in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start: \(date.formatted(date: .abbreviated, time: .omitted))")
                            Text(store.history.periodEnds[date].map {
                                "End: \($0.formatted(date: .abbreviated, time: .omitted))"
                            } ?? "End not recorded")
                            HStack {
                                Button("Edit / record end") {
                                    original = date; start = date
                                    hasEnd = store.history.periodEnds[date] != nil
                                    end = store.history.periodEnds[date] ?? .now
                                }
                                Button("Delete", role: .destructive) { deleting = date }
                            }.buttonStyle(.borderless)
                        }
                    }
                    Text("Deleting a period date retains daily entries and recalculates their cycle assignment.").font(.caption)
                }
            }
            .navigationTitle("Period dates")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this period record? Daily entries will stay.",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete period", role: .destructive) {
                    if let date = deleting { store.deletePeriod(start: date) }
                    deleting = nil
                }
            }
        }
    }
}
