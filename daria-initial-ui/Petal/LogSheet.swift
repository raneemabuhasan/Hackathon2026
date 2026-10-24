import SwiftUI

@MainActor
struct LogSheet: View {
    var moodOnly = false
    var symptomsOnly = false
    var flowOnly = false
    @State private var editingCustomFlow = false
    @State private var customFlowName = ""
    @Environment(\.dismiss) private var dismiss
    @State private var savingIndividual = false
    @State private var individualError: String?
    @Environment(CycleStore.self) private var store
    @State private var logDate = Calendar.current.startOfDay(for: .now)
    @State private var flow = "None"
    @State private var moods: Set<String> = []
    @State private var symptoms: Set<String> = []
    @State private var pain = 0.0
    @State private var energy = 3.0
    @State private var note = ""
    @State private var viewingSavedLog = false
    @State private var confirmingLogDeletion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingMoods = false
    @State private var editingSymptoms = false
    @State private var tagEditor: TagEditRequest?

    private struct TagEditRequest: Identifiable {
        let id = UUID()
        let symptom: Bool
        let originalName: String? // nil when adding a new tag
        let emoji: String
    }

    private var flows: [(String, Int)] {
        let standard = [("None", 0), ("Light", 1), ("Medium", 2), ("Heavy", 3)]
        return standard.contains(where: { $0.0 == flow }) ? standard : standard + [(flow, 1)]
    }
    private let energyLevels = [("Drained", "battery.0percent"), ("Low", "battery.25percent"), ("Steady", "battery.50percent"),
                                ("Good", "battery.75percent"), ("Energised", "battery.100percent")]
    private static let emoji: [String: String] = [
        "Calm": "😌", "Happy": "😊", "Confident": "😎", "Tired": "😴", "Anxious": "😰", "Irritable": "😤", "Low": "😔", "Sensitive": "🥺",
        "Cramps": "🌀", "Headache": "🤕", "Bloating": "🎈", "Tender breasts": "👙", "Back pain": "🦴", "Acne": "🧴",
        "Fatigue": "🪫", "Cravings": "🍫", "Trouble sleeping": "🌙", "Low sex drive": "🥀", "High sex drive": "🔥",
    ]
    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        Group {
            if moodOnly || symptomsOnly || flowOnly { individualBody } else { combinedBody }
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .animation(.easeOut(duration: 0.2), value: pain >= 7)
        .sheet(item: $tagEditor) { request in
            TagEditorSheet(symptom: request.symptom,
                           originalName: request.originalName,
                           initialEmoji: request.emoji) { name, emoji in
                guard let updated = store.saveEditableTag(symptom: request.symptom,
                                                          original: request.originalName,
                                                          name: name, emoji: emoji) else { return false }
                if request.symptom {
                    if let previous = request.originalName {
                        if symptoms.remove(previous) != nil { symptoms.insert(updated) }
                    } else {
                        symptoms.insert(updated)
                    }
                } else {
                    if let previous = request.originalName {
                        if moods.remove(previous) != nil { moods.insert(updated) }
                    } else {
                        moods.insert(updated)
                    }
                }
                return true
            }
        }
        .alert("Custom flow", isPresented: $editingCustomFlow) {
            TextField("Flow label", text: $customFlowName)
            Button("Cancel", role: .cancel) { }
            Button("Use flow") {
                let name = customFlowName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { flow = name }
            }
            .disabled(customFlowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customFlowName.count > 30)
        } message: {
            Text("Name the flow you want to record (up to 30 characters).")
        }
        .confirmationDialog("Delete this saved log?", isPresented: $confirmingLogDeletion, titleVisibility: .visible) {
            Button("Delete log", role: .destructive) {
                if let saved = store.log(for: logDate) {
                    store.deleteLog(saved)
                    store.showLog = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This entry will be removed from your symptom history. Recorded period dates will be kept.")
        }
        .onAppear {
            logDate = store.selectedLogDate ?? store.today
            loadDraft(for: logDate)
            // Tapping a saved row previews it. The + button still opens the editor.
            viewingSavedLog = store.showingLogPreview && store.log(for: logDate) != nil
        }
        .onDisappear { store.selectedLogDate = nil; store.showingLogPreview = false }
    }

    private var combinedBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    DisplayTitle(before: viewingSavedLog ? "How you " : "How do you ",
                                 accent: viewingSavedLog ? "felt" : "feel?", size: 32)
                    Spacer()
                    Button { store.showLog = false } label: {
                        Image(systemName: "xmark").font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .disabled(store.logWritePending)
                }
                if viewingSavedLog {
                    savedLogDetails
                } else {
                    combinedFields
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .background(Palette.bg.ignoresSafeArea())
        .interactiveDismissDisabled(store.logWritePending)
        .onChange(of: store.logsLoaded) { _, loaded in
            if loaded { loadDraft(for: logDate) }
        }
    }

    private var combinedFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            DatePicker("Log date", selection: $logDate, in: ...store.today, displayedComponents: .date)
                .font(.system(size: 14, weight: .semibold))
                .padding(.vertical, 8)
                .onChange(of: logDate) { _, date in loadDraft(for: date) }
            individualFlow
            tagSection(store.allMoods, selected: $moods, symptom: false)
            tagSection(store.allSymptoms, selected: $symptoms, symptom: true)
            individualPain
            individualEnergy
            VStack(alignment: .leading, spacing: 12) {
                Text("Note").font(.cardSubheading)
                TextField("Anything you want to remember…", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
            }
            if !store.logsLoaded { ProgressView("Loading saved entry") }
            if let error = store.logWriteError ?? store.logsError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if store.logWritePending { ProgressView("Saving entry") }
            Button {
                store.save(DayLog(date: logDate, flow: flow, moods: moods.sorted(), symptoms: symptoms.sorted(),
                                  pain: Int(pain), energy: Int(energy), note: note))
            } label: {
                Text("Save log").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.surface)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Palette.surface2.opacity(0.45), in: RoundedRectangle(cornerRadius: 24))
        .disabled(store.logWritePending || !store.logsLoaded || store.logsError != nil)
    }


    private var individualBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Log \(Text(flowOnly ? "Flow" : (symptomsOnly ? "Symptoms" : "Mood")).italic().foregroundStyle(Palette.accent))")
                        .font(.display(32))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .disabled(savingIndividual)
                }
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(flowOnly ? "How is your flow?" : (symptomsOnly ? "What are you noticing?" : "How are you feeling?")).font(.cardSubheading)
                        Text(flowOnly ? "Choose the option that best describes your flow." : (symptomsOnly ? "Select any symptoms, then record your pain and energy." : "Select your moods or add your own."))
                            .font(.system(size: 16)).foregroundStyle(Palette.inkSoft)
                    }
                    DatePicker("Log date", selection: $logDate, in: ...store.today, displayedComponents: .date)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 8)
                        .onChange(of: logDate) { _, date in loadDraft(for: date) }
                    if flowOnly {
                        individualFlow
                    } else if symptomsOnly {
                        tagSection(store.allSymptoms, selected: $symptoms, symptom: true)
                        individualPain
                        individualEnergy
                    } else {
                        tagSection(store.allMoods, selected: $moods, symptom: false)
                    }
                    if !store.logsLoaded { ProgressView("Loading saved entry") }
                    if let error = individualError ?? store.logsError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button(action: saveIndividual) {
                        HStack {
                            if savingIndividual { ProgressView().tint(Palette.surface) }
                            Text(flowOnly ? "Save flow" : (symptomsOnly ? "Save symptoms" : "Save mood")).font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(Palette.surface)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingIndividual || !store.logsLoaded || store.logsError != nil || store.logWritePending)
                }
                .padding(18)
                .background(Palette.surface2.opacity(0.45), in: RoundedRectangle(cornerRadius: 24))
                .disabled(savingIndividual)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .background(Palette.bg.ignoresSafeArea())
        .interactiveDismissDisabled(savingIndividual)
        .onChange(of: store.logsLoaded) { _, loaded in
            if loaded { loadDraft(for: logDate) }
        }
    }

    private var standardFlowNames: [String] { ["None", "Spotting", "Light", "Medium", "Heavy"] }

    private var individualFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flow").font(.cardSubheading)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
                ForEach(Array(standardFlowNames.enumerated()), id: \.element) { index, name in
                    Button { flow = name } label: {
                        flowTile(name: name, index: index, selected: flow == name)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(flow == name ? .isSelected : [])
                }
                Button {
                    customFlowName = standardFlowNames.contains(flow) ? "" : flow
                    editingCustomFlow = true
                } label: {
                    flowTile(name: standardFlowNames.contains(flow) ? "Custom" : flow,
                             index: nil, selected: !standardFlowNames.contains(flow))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(standardFlowNames.contains(flow) ? "Custom flow" : "Custom flow, \(flow)")
                .accessibilityAddTraits(standardFlowNames.contains(flow) ? [] : .isSelected)
            }
        }
    }

    private func flowTile(name: String, index: Int?, selected: Bool) -> some View {
        VStack(spacing: 12) {
            if let index {
                Image(systemName: index == 0 ? "drop" : "drop.fill")
                    .font(.system(size: CGFloat(24 + index * 5)))
                    .foregroundStyle([Palette.inkFaint, Palette.petal, Palette.pink, Palette.accent, Palette.berry][index])
                    .frame(width: 68, height: 68)
                    .background(Palette.accentSoft, in: Circle())
            } else {
                Image(systemName: "plus").font(.system(size: 36, weight: .light))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 68, height: 68)
            }
            Text(name).font(.system(size: 15, weight: .semibold))
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 144)
        .padding(.horizontal, 8)
        .background(selected ? Palette.blushPink : Palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(selected ? Palette.accent : Palette.line,
                    style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: index == nil ? [4, 3] : [])))
        .foregroundStyle(selected ? Palette.ink : (index == nil ? Palette.accent : Palette.ink))
    }

    private var individualPain: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pain").font(.cardSubheading)
                Spacer()
                Text("How much pain today?").font(.system(size: 14))
                    .foregroundStyle(Palette.inkSoft)
            }
            gradientPainSlider
            HStack(spacing: 0) {
                ForEach(0...10, id: \.self) { level in
                    Text("\(level)")
                        .font(.system(size: 12, weight: Int(pain) == level ? .bold : .regular))
                        .foregroundStyle(Int(pain) == level ? Palette.accent : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            if pain >= 7 {
                Text("Pain that stops you doing everyday things deserves proper care. Consider talking to a GP or pharmacist.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
                Link("NHS: period pain", destination: CycleStore.nhsPeriodPain).font(.caption)
            }
        }
    }

    private var gradientPainSlider: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 30)
            let progress = min(1, max(0, pain / 10))
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.accentSoft)
                    .frame(height: 8)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.petal, Palette.pink,
                                                  Palette.accent, Palette.berry],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: 15 + travel * progress)
                    }
                Circle().fill(Palette.surface)
                    .overlay(Circle().stroke(Self.painColor(Int(pain)), lineWidth: 3))
                    .shadow(color: Self.painColor(Int(pain)).opacity(0.2), radius: 4, y: 2)
                    .frame(width: 30, height: 30)
                    .offset(x: travel * progress)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                pain = (min(1, max(0, (value.location.x - 15) / travel)) * 10).rounded()
            })
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Pain")
        .accessibilityValue("\(Int(pain)) out of 10")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: pain = min(10, pain + 1)
            case .decrement: pain = max(0, pain - 1)
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: Int(pain))
    }

    private var individualEnergy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Energy").font(.cardSubheading)
            HStack(spacing: 6) {
                ForEach(Array(energyLevels.enumerated()), id: \.offset) { index, level in
                    let selected = Int(energy) == index + 1
                    Button { energy = Double(index + 1) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: level.1).font(.system(size: 20))
                                .foregroundStyle(selected ? Palette.accent : Palette.inkFaint)
                            Text(level.0).foregroundStyle(selected ? Palette.ink : Palette.ink)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(selected ? Palette.blushPink : Palette.surface,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy \(level.0)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func saveIndividual() {
        guard !savingIndividual, store.logsLoaded, store.logsError == nil, !store.logWritePending else { return }
        savingIndividual = true
        individualError = nil
        // Update only this sheet’s fields in the latest daily entry.
        var entry = store.log(for: logDate) ?? DayLog(date: logDate)
        if flowOnly {
            entry.flow = flow
        } else if symptomsOnly {
            entry.symptoms = symptoms.sorted()
            entry.pain = Int(pain)
            entry.energy = Int(energy)
        } else {
            entry.moods = moods.sorted()
        }
        Task {
            defer { savingIndividual = false }
            do {
                try await store.write(entry)
                store.showToast(flowOnly ? "Flow saved" : (symptomsOnly ? "Symptoms saved" : "Mood saved"))
                dismiss()
            } catch { individualError = "Entry wasn't saved: \(error.localizedDescription)" }
        }
    }

    /// A saved day log is a readable journal entry until the user taps Edit.
    @ViewBuilder private var savedLogDetails: some View {
        if let saved = store.log(for: logDate) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    Image(systemName: "calendar")
                        .foregroundStyle(Palette.accent)
                    Text(logDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer(minLength: 8)
                    Button {
                        viewingSavedLog = false
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
                    .accessibilityLabel("Edit this saved day log")
                    Button {
                        confirmingLogDeletion = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
                    .accessibilityLabel("Delete this saved day log")
                    .disabled(store.logWritePending)
                }

                // Flow gets the same droplet language as the log editor.
                VStack(alignment: .leading, spacing: 9) {
                    Label("Flow", systemImage: "drop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 5) {
                        let manualWithoutSavedFlow = saved.flow == "None" && store.periodHistory.contains(logDate)
                        let drops = flows.first(where: { $0.0 == saved.flow })?.1 ?? 0
                        if drops == 0 {
                            Image(systemName: "drop")
                                .foregroundStyle(Palette.inkFaint)
                        } else {
                            ForEach(0..<drops, id: \.self) { _ in
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        Text(manualWithoutSavedFlow ? "Period marked · choose flow" :
                             saved.flow == "None" ? "Not recorded" : saved.flow)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.surface2.opacity(0.32), in: RoundedRectangle(cornerRadius: 13))
                }

                savedTagSection("Moods", icon: "face.smiling", tags: saved.moods, symptom: false)
                savedTagSection("Symptoms", icon: "heart.text.square", tags: saved.symptoms, symptom: true)

                HStack(spacing: 10) {
                    savedStat("Pain", icon: "waveform.path.ecg",
                              value: saved.pain == 0 ? "None" : "\(saved.pain) / 10")
                    savedStat("Energy",
                              icon: energyLevels[max(0, min(energyLevels.count - 1, saved.energy - 1))].1,
                              value: "\(saved.energy) / 5")
                }

                VStack(alignment: .leading, spacing: 9) {
                    Label("Note", systemImage: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(saved.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "No note for this day." : saved.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Palette.surface2.opacity(0.32), in: RoundedRectangle(cornerRadius: 13))
                }
            }
            .padding(17)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
        } else {
            Text("This saved log is no longer available.")
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private func savedTagSection(_ title: String, icon: String,
                                 tags: [String], symptom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if tags.isEmpty {
                Text("None recorded")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface2.opacity(0.32), in: RoundedRectangle(cornerRadius: 13))
            } else {
                LazyVGrid(columns: tileColumns, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        let icon = store.emojiForTag(symptom: symptom, tag)
                    ?? (symptom ? ["Cramps": "⚡️", "Headache": "🤕", "Bloating": "🫧", "Tender breasts": "👙"][tag] : nil)
                    ?? Self.emoji[tag] ?? "✨"
                        VStack(spacing: 5) {
                            Text(icon).font(.system(size: 23))
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 67)
                        .padding(.horizontal, 3)
                        .background(Palette.surface2.opacity(0.32),
                                    in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }
        }
    }

    private func savedStat(_ title: String, icon: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Palette.surface2.opacity(0.32), in: RoundedRectangle(cornerRadius: 13))
    }

    /// Fills the form from that day's saved log, or blank defaults (no flow, pain 0, steady energy).
    private func loadDraft(for date: Date) {
        if let saved = store.log(for: date) {
            flow = store.flowForLog(on: date, saved: saved.flow)
            moods = Set(saved.moods)
            symptoms = Set(saved.symptoms)
            pain = Double(saved.pain)
            energy = Double(saved.energy)
            note = saved.note
        } else {
            flow = store.flowForLog(on: date)
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

    /// The management bar only affects Mood and Symptoms; Flow and all other fields stay unchanged.
    private func tagSection(_ tags: [String], selected: Binding<Set<String>>, symptom: Bool) -> some View {
        let managing = symptom ? editingSymptoms : editingMoods
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !moodOnly && !flowOnly { Text(symptom ? "Symptoms" : "Mood").font(.cardSubheading) }
                Spacer()
                Button(managing ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if symptom {
                            editingSymptoms.toggle()
                            editingMoods = false
                        } else {
                            editingMoods.toggle()
                            editingSymptoms = false
                        }
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityLabel(managing ? "Finish editing tags" : "Edit tags")
            }
            if managing {
                Text("Hold and drag to reorder · Tap − to remove · Double-tap to rename or change emoji")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSoft)
            }
            tagGrid(tags, selected: selected, symptom: symptom, managing: managing)
        }
    }

    private func tagGrid(_ tags: [String], selected: Binding<Set<String>>, symptom: Bool, managing: Bool) -> some View {
        // Include archived tags still selected in an existing day's log so editing never loses data.
        let shown = tags + selected.wrappedValue.filter { !tags.contains($0) }.sorted()
        return LazyVGrid(columns: tileColumns, spacing: 8) {
            ForEach(shown, id: \.self) { tag in
                let on = selected.wrappedValue.contains(tag)
                let icon = store.emojiForTag(symptom: symptom, tag)
                    ?? (symptom ? ["Cramps": "⚡️", "Headache": "🤕", "Bloating": "🫧", "Tender breasts": "👙"][tag] : nil)
                    ?? Self.emoji[tag] ?? "✨"
                if managing {
                    tile(emoji: icon, label: tag, on: on)
                        .phaseAnimator([false, true]) { content, phase in
                            content.rotationEffect(.degrees(reduceMotion ? 0 : (phase ? 1.4 : -1.4)))
                        } animation: { _ in .easeInOut(duration: 0.17) }
                        .onTapGesture(count: 2) { editTag(tag, symptom: symptom) }
                        .draggable(tag)
                        .dropDestination(for: String.self) { items, _ in
                            guard let source = items.first else { return false }
                            store.moveTag(symptom: symptom, from: source, to: tag)
                            return true
                        }
                        .overlay(alignment: .topLeading) {
                            Button {
                                store.removeTag(symptom: symptom, tag)
                                selected.wrappedValue.remove(tag)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 21))
                                    .foregroundStyle(Palette.accent)
                                    .background(Palette.surface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(tag) from my list")
                            .offset(x: -5, y: -5)
                        }
                        .accessibilityLabel("\(tag), hold and drag to reorder or double tap to edit")
                } else {
                    Button { toggle(&selected.wrappedValue, tag) } label: {
                        tile(emoji: icon, label: tag, on: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tag)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .contextMenu {
                        Button { editTag(tag, symptom: symptom) } label: {
                            Label("Edit name or emoji", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.removeTag(symptom: symptom, tag)
                            selected.wrappedValue.remove(tag)
                        } label: {
                            Label("Remove from my list", systemImage: "trash")
                        }
                    }
                }
            }
            Group {
                Button {
                    tagEditor = TagEditRequest(symptom: symptom, originalName: nil,
                                               emoji: symptom ? "🌀" : "😊")
                } label: {
                    tile(emoji: "＋", label: symptom ? "Add symptom" : "Add mood", on: false, dashed: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symptom ? "Add your own symptom" : "Add your own mood")
            }
        }
    }

    private func editTag(_ name: String, symptom: Bool) {
        let emoji = store.emojiForTag(symptom: symptom, name) ?? Self.emoji[name] ?? (symptom ? "🌀" : "😊")
        tagEditor = TagEditRequest(symptom: symptom, originalName: name, emoji: emoji)
    }

    @ViewBuilder private func tile(emoji: String, label: String, on: Bool, dashed: Bool = false) -> some View {
            VStack(spacing: 6) {
                Text(emoji).font(.system(size: dashed ? 30 : 24))
                    .frame(width: 38, height: 38)
                    .background(dashed ? Color.clear : Palette.accentSoft, in: Circle())
                Text(label).font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(on ? Palette.blushPink : Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(on ? Palette.accent : Palette.line,
                        style: StrokeStyle(lineWidth: on ? 1.5 : 1, dash: dashed ? [4, 3] : [])))
            .foregroundStyle(on ? Palette.ink : (dashed ? Palette.accent : Palette.ink))
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
        let steps: [Color] = [Palette.petal, Palette.pink, Palette.accent, Palette.berry]
        return steps[min(steps.count - 1, max(0, level) * steps.count / 11)]
    }


}

// A compact name + emoji editor. Built-in tags may be renamed (converted into custom tags);
// previously saved logs remain unchanged so the history stays accurate.
@MainActor
private struct TagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let symptom: Bool
    let originalName: String?
    let onSave: (String, String) -> Bool
    @State private var name: String
    @State private var emoji: String
    @State private var showingEmojiPicker = false
    @State private var showNameError = false

    init(symptom: Bool, originalName: String?, initialEmoji: String,
         onSave: @escaping (String, String) -> Bool) {
        self.symptom = symptom
        self.originalName = originalName
        self.onSave = onSave
        _name = State(initialValue: originalName ?? "")
        _emoji = State(initialValue: initialEmoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(symptom ? "Symptom" : "Mood") {
                    Button {
                        showingEmojiPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(emoji).font(.system(size: 30))
                            Image(systemName: "face.smiling").foregroundStyle(Palette.accent)
                            Text("Choose emoji").foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.inkFaint)
                        }
                    }
                    .accessibilityLabel("Choose emoji, currently \(emoji)")
                    TextField(symptom ? "e.g. Joint pain" : "e.g. Restless", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: name) { _, _ in showNameError = false }
                }
                if showNameError {
                    Text("Use a unique name of 1–30 characters.")
                        .font(.footnote).foregroundStyle(.red)
                }
                Text("Choose a \(symptom ? "general emoji" : "face emoji") and a name. Changes affect future choices; saved daily entries keep their original labels.")
                    .font(.footnote).foregroundStyle(Palette.inkSoft)
            }
            .navigationTitle(originalName == nil ? (symptom ? "New symptom" : "New mood") : "Edit tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(name, emoji) { dismiss() } else { showNameError = true }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(Palette.accent)
            .sheet(isPresented: $showingEmojiPicker) {
                PetalEmojiPicker(symptom: symptom, emoji: $emoji)
            }
        }
    }
}

/// Apple-style emoji grid. iOS does not expose a system emoji keyboard filtered to faces,
/// so moods use a curated face-only selection and symptoms use broader emoji categories.
@MainActor
private struct PetalEmojiPicker: View {
    @Environment(\.dismiss) private var dismiss
    let symptom: Bool
    @Binding var emoji: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let faces = "😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 🤐 🤨 😐 😑 😶 🫥 😏 😒 🙄 😬 😮‍💨 🤥 🫨 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 😵‍💫 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 🫤 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿".split(separator: " ").map(String.init)
    private let symptomGroups: [(String, String)] = [
        ("Faces & feelings", "😀 😊 🥺 😷 🤕 🤒 😴 😰 🤢 😵 😡 🥵 😢 🤯 😩 😮‍💨 🥹 😌"),
        ("Body & wellbeing", "💊 🩹 💉 🩺 🧠 🫀 🫁 🦷 🦴 👀 👂 👃 👄 🦵 🦶 ✋ 🤲 💪 🩸 🧘 🚶 🛌 💤 ♨️"),
        ("Food, nature & symbols", "🍫 🍪 🍦 🍎 🍋 🍵 ☕ 💧 🌊 🌧️ 🌙 ☀️ 🌸 🌺 🍃 🌱 🪷 ⭐ ✨ 🌈 🔥 💥 ⚡ 💫 ❤️ 💔 💕 💖 💗 🧊 🎈 🌀 💢 ❗ ⚠️")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if symptom {
                        ForEach(symptomGroups, id: \.0) { title, symbols in
                            emojiGroup(title, values: symbols.split(separator: " ").map(String.init))
                        }
                    } else {
                        emojiGroup("Faces", values: faces)
                    }
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle(symptom ? "Choose an emoji" : "Choose a face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .tint(Palette.accent)
        }
        .presentationDetents([.medium, .large])
    }

    private func emojiGroup(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(values, id: \.self) { symbol in
                    Button {
                        emoji = symbol
                        dismiss()
                    } label: {
                        Text(symbol)
                            .font(.system(size: 27))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(emoji == symbol ? Palette.accentSoft : Palette.surface,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose \(symbol)")
                }
            }
        }
    }
}
