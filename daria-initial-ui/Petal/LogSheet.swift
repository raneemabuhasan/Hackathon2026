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
    /// Which list the "+ Add" alert is adding to (true = symptoms), nil when closed.
    @State private var addingSymptom: Bool?
    @State private var newTag = ""

    private let flows = [("None", 0), ("Light", 1), ("Medium", 2), ("Heavy", 3)]
    private let energyLevels = [("Drained", "battery.0percent"), ("Low", "battery.25percent"), ("Steady", "battery.50percent"),
                                ("Good", "battery.75percent"), ("Energised", "battery.100percent")]
    private static let emoji: [String: String] = [
        "Calm": "😌", "Happy": "😊", "Confident": "😎", "Tired": "😴", "Anxious": "😰", "Irritable": "😤", "Low": "😔", "Sensitive": "🥺",
        "Cramps": "🌀", "Headache": "🤕", "Bloating": "🎈", "Tender breasts": "👙", "Back pain": "🦴", "Acne": "🧴",
        "Fatigue": "🪫", "Cravings": "🍫", "Trouble sleeping": "🌙",
    ]
    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

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

                if let error = store.logWriteError { Text(error).font(.caption).foregroundStyle(.red) }
                if store.logWritePending { ProgressView("Saving entry") }

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
                    tagGrid(store.allMoods, selected: $moods, custom: store.profile?.customMoods ?? [], symptom: false)
                }

                field("Symptoms") {
                    tagGrid(store.allSymptoms, selected: $symptoms, custom: store.profile?.customSymptoms ?? [], symptom: true)
                }

                field("Pain", value: "\(Self.painWord(Int(pain))) · \(Int(pain))") {
                    painScale
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

                field("Energy") {
                    HStack(spacing: 6) {
                        ForEach(Array(energyLevels.enumerated()), id: \.offset) { i, level in
                            let selected = Int(energy) == i + 1
                            Button { energy = Double(i + 1) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: level.1).font(.system(size: 18)).foregroundStyle(selected ? Palette.accent : Palette.inkFaint)
                                    Text(level.0).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selected ? Palette.accentSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Palette.accent : Palette.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Energy \(level.0)")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
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
                .disabled(store.logWritePending)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .animation(.easeOut(duration: 0.2), value: pain >= 7)
        .alert(addingSymptom == true ? "Add a symptom" : "Add a mood", isPresented: Binding(get: { addingSymptom != nil }, set: { if !$0 { addingSymptom = nil } })) {
            TextField(addingSymptom == true ? "e.g. Joint pain" : "e.g. Restless", text: $newTag)
            Button("Add") {
                let symptom = addingSymptom == true
                if let tag = store.addCustom(symptom: symptom, newTag) {
                    if symptom { symptoms.insert(tag) } else { moods.insert(tag) }
                }
                newTag = ""
            }
            Button("Cancel", role: .cancel) { newTag = "" }
        } message: {
            Text("It'll be saved to your list for next time.")
        }
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

    /// Emoji tiles for moods or symptoms, with the user's own tags and a "+ Add" tile at the end.
    private func tagGrid(_ tags: [String], selected: Binding<Set<String>>, custom: [String], symptom: Bool) -> some View {
        // Keep anything already on this day's log visible, even if it was removed from the custom list.
        let shown = tags + selected.wrappedValue.filter { !tags.contains($0) }.sorted()
        return LazyVGrid(columns: tileColumns, spacing: 8) {
            ForEach(shown, id: \.self) { tag in
                let on = selected.wrappedValue.contains(tag)
                Button { toggle(&selected.wrappedValue, tag) } label: {
                    tile(emoji: Self.emoji[tag] ?? "✨", label: tag, on: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tag)
                .accessibilityAddTraits(on ? .isSelected : [])
                .contextMenu {
                    if custom.contains(tag) {
                        Button("Remove from my list", role: .destructive) { store.removeCustom(symptom: symptom, tag) }
                    }
                }
            }
            Button { addingSymptom = symptom } label: {
                tile(emoji: "＋", label: "Add", on: false, dashed: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(symptom ? "Add your own symptom" : "Add your own mood")
        }
    }

    private func tile(emoji: String, label: String, on: Bool, dashed: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 22))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.horizontal, 4)
        .background(on ? Palette.accentSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(on ? Palette.accent : Palette.line, style: StrokeStyle(lineWidth: on ? 1.5 : 1, dash: dashed ? [4, 3] : []))
        )
        .foregroundStyle(dashed ? Palette.accent : Palette.ink)
    }

    /// 0-10 scale that works like a slider: drag or tap along the dots. Dots up to the level fill with the gradient.
    private var painScale: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let step = geo.size.width / 11
                ZStack(alignment: .leading) {
                    // Track behind the dots, filled up to the current level.
                    Capsule().fill(Palette.ink.opacity(0.1))
                        .frame(width: step * 10, height: 4)
                        .offset(x: step / 2)
                    Capsule().fill(LinearGradient(colors: [Self.painColor(0), Self.painColor(Int(pain))], startPoint: .leading, endPoint: .trailing))
                        .frame(width: step * pain, height: 4)
                        .offset(x: step / 2)
                    HStack(spacing: 0) {
                        ForEach(0...10, id: \.self) { level in
                            let filled = level <= Int(pain)
                            let current = level == Int(pain)
                            Circle()
                                .fill(filled ? Self.painColor(level) : Palette.surface)
                                .overlay(Circle().stroke(current ? Palette.ink : (filled ? Color.clear : Palette.ink.opacity(0.22)),
                                                         lineWidth: current ? 2 : 1.5))
                                .frame(width: current ? 26 : 16, height: current ? 26 : 16)
                                .frame(width: step, height: 32)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    pain = Double(min(10, max(0, Int(drag.location.x / step))))
                })
            }
            .frame(height: 32)
            .sensoryFeedback(.selection, trigger: Int(pain))
            .accessibilityElement()
            .accessibilityLabel("Pain")
            .accessibilityValue("\(Int(pain)) out of 10, \(Self.painWord(Int(pain)))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: pain = min(10, pain + 1)
                case .decrement: pain = max(0, pain - 1)
                @unknown default: break
                }
            }
            HStack {
                Text("None"); Spacer(); Text("Moderate"); Spacer(); Text("Severe")
            }
            .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
        }
        .animation(.spring(duration: 0.15), value: pain)
    }

    static func painWord(_ level: Int) -> String {
        switch level {
        case 0: "None"
        case 1...3: "Mild"
        case 4...6: "Moderate"
        case 7...8: "Strong"
        default: "Severe"
        }
    }

    private static func painColor(_ level: Int) -> Color {
        // Starts at a mid pink so the low levels are still easy to see on the pale background.
        let steps = [Palette.petal, Palette.pink, Palette.coral, Palette.rose, Palette.berry, Palette.plum, Palette.wine]
        return steps[min(steps.count - 1, level * steps.count / 11)]
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
