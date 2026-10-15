import SwiftUI

@MainActor
struct LogSheet: View {
    @Environment(CycleStore.self) private var store
    @State private var logDate = Calendar.current.startOfDay(for: .now)
    @State private var flow = "None"
    @State private var moods: Set<String> = []
    @State private var symptoms: Set<String> = []
    @State private var pain = 0.0
    @State private var energy = 3.0
    @State private var note = ""

    private let flows = [("None", 0), ("Light", 1), ("Medium", 2), ("Heavy", 3)]
    private let energyLabels = ["Drained", "Low", "Steady", "Good", "Glowing"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Log · " + logDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        DisplayTitle(before: "How are you ", accent: "today?", size: 30)
                    }
                    Spacer()
                    Button { store.showLog = false } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                DatePicker("Log date", selection: $logDate, in: ...store.today, displayedComponents: .date)
                    .font(.system(size: 14, weight: .semibold))
                    .onChange(of: logDate) { _, newDate in loadDraft(for: newDate) }

                field("Flow") {
                    HStack(spacing: 8) {
                        ForEach(flows, id: \.0) { name, drops in
                            Button { flow = name } label: {
                                VStack(spacing: 6) {
                                    HStack(alignment: .bottom, spacing: 2) {
                                        if drops == 0 {
                                            Image(systemName: "drop").font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
                                        }
                                        ForEach(0..<drops, id: \.self) { i in
                                            Image(systemName: "drop.fill").font(.system(size: CGFloat(9 + i * 3))).foregroundStyle(Palette.accent)
                                        }
                                    }
                                    .frame(height: 18)
                                    Text(name).font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(flow == name ? Palette.accentSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(flow == name ? Palette.accent : Palette.line))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                field("Mood") {
                    FlowLayout {
                        ForEach(CycleStore.moodOptions, id: \.self) { m in
                            Chip(label: m, selected: moods.contains(m)) { toggle(&moods, m) }
                        }
                    }
                }

                field("Symptoms") {
                    FlowLayout {
                        ForEach(CycleStore.symptomOptions, id: \.self) { s in
                            Chip(label: s, selected: symptoms.contains(s)) { toggle(&symptoms, s) }
                        }
                    }
                }

                field("Pain level", value: "\(Int(pain)) / 10") {
                    Slider(value: $pain, in: 0...10, step: 1)
                    if pain >= 7 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pain that stops you doing everyday things deserves proper care. Consider talking to a GP or pharmacist.")
                            Link("NHS: period pain", destination: CycleStore.nhsPeriodPain).foregroundStyle(Palette.accent)
                        }
                        .font(.system(size: 13))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                field("Energy", value: energyLabels[Int(energy) - 1]) {
                    Slider(value: $energy, in: 1...5, step: 1)
                }

                field("Note") {
                    TextField("Anything you want to remember…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line))
                }

                Button {
                    store.save(DayLog(date: logDate, flow: flow, moods: moods.sorted(), symptoms: symptoms.sorted(),
                                      pain: Int(pain), energy: Int(energy), note: note))
                } label: {
                    Text("Save log")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .animation(.easeOut(duration: 0.2), value: pain >= 7)
        .onAppear {
            logDate = store.selectedLogDate ?? store.today
            loadDraft(for: logDate)
        }
        .onDisappear { store.selectedLogDate = nil }
    }

    /// Fills the form from that day's saved log, or blank defaults (no flow, pain 0, steady energy).
    private func loadDraft(for date: Date) {
        if let saved = store.log(for: date) {
            flow = saved.flow
            moods = Set(saved.moods)
            symptoms = Set(saved.symptoms)
            pain = Double(saved.pain)
            energy = Double(saved.energy)
            note = saved.note
        } else {
            flow = "None"
            moods = []
            symptoms = []
            pain = 0
            energy = 3
            note = ""
        }
    }

    private func toggle(_ set: inout Set<String>, _ value: String) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func field<C: View>(_ title: String, value: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let value { Text(value).font(.system(size: 14)).monospacedDigit().foregroundStyle(Palette.inkSoft) }
            }
            content()
        }
    }
}
