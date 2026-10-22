import SwiftUI

@MainActor
struct CompanionView: View {
    @Environment(CycleStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var editing: ReminderSheet?

    /// Which reminder the editor sheet is open for.
    private enum ReminderSheet: Identifiable {
        case new, edit(Reminder)
        var id: String { if case let .edit(r) = self { return r.id } else { return "new" } }
    }

    private let prompts = ["When is my next period?", "Remind me to restock pads", "I have cramps", "What should I eat today?"]

    var body: some View {
        ScrollViewReader { proxy in
            Page {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Companion")
                    DisplayTitle(before: "Your ", accent: "companion")
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Reminders", trailing: "tap to edit")
                    ForEach(store.reminders) { r in
                        HStack(spacing: 12) {
                            Button { editing = .edit(r) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.text(name: store.name)).font(.system(size: 14, weight: .semibold))
                                    Text(r.detail(windowStart: store.windowStart)).font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Toggle(r.text(name: store.name), isOn: Binding(get: { r.on }, set: { store.setReminder(r, on: $0) }))
                                .labelsHidden()
                                .tint(Palette.accent)
                        }
                        .padding(.vertical, 8)
                    }
                    Button { editing = .new } label: {
                        Label("New reminder", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
                .card()
                .sheet(item: $editing) { target in
                    ReminderEditor(reminder: { if case let .edit(r) = target { return r } else { return nil } }())
                        .environment(store)
                        .presentationDetents([.large])
                        .presentationCornerRadius(32)
                        .presentationBackground(Palette.bg)
                }

                if !store.aiEnabled {
                    aiOffCard
                } else {
                FlowLayout {
                    ForEach(prompts, id: \.self) { p in
                        Chip(label: p, selected: false, small: true) { store.send(p) }
                            .disabled(store.thinking)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(store.messages) { m in
                        bubble(m).id(m.id)
                    }
                    if store.thinking {
                        Text("Thinking…")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("thinking")
                    }
                }
                }
            }
            .onChange(of: store.messages.count) {
                if let last = store.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.aiEnabled { inputBar }
        }
    }

    /// Shown instead of the chat until the user opts in to sending data to Gemini.
    private var aiOffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat is off").font(.system(size: 15, weight: .semibold))
            Text("The companion uses Google's Gemini AI through Firebase. To answer you, Sync sends your messages with your cycle dates, recent logs and food preferences. It's general wellness info, not medical advice.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button { store.setAIConsent(true) } label: {
                Text("Turn on companion")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .card()
    }

    private var inputBar: some View {
            HStack(spacing: 8) {
                TextField("Ask your companion...", text: $draft)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                if focused {
                    Button {
                        focused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss keyboard")
                }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Palette.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(store.thinking)
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .background(Palette.surface, in: Capsule())
            .shadow(color: Palette.berry.opacity(0.1), radius: 12, y: 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.thinking else { return }
        draft = ""
        store.send(text)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.fromUser {
            Text(m.text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.accent, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
                .frame(maxWidth: 300, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(m.text)
                    .font(!m.recordedCycles.isEmpty && m.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Here are your recorded cycles:"
                          ? .headline : .system(size: 14))
                ForEach(m.educationCitations) { citation in
                    Link(destination: citation.url) {
                        Text("[\(citation.number)] \(citation.sourceTitle) · \(citation.passageTitle)")
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Source \(citation.number): \(citation.sourceTitle), \(citation.passageTitle)")
                }
                if m.educationCitations.contains(where: { $0.sourceID == "cc-cycle-syncing" }) {
                    Text("Cycle-syncing programs lack clinical research. Food ideas are optional, not treatments or hormone-balancing methods.")
                        .font(.caption).foregroundStyle(Palette.inkSoft)
                }
                ForEach(m.suggestedPrompts, id: \.self) { prompt in
                    Button(prompt) { store.send(prompt) }
                        .font(.caption).foregroundStyle(Palette.accent)
                        .padding(8).background(Palette.surface2, in: Capsule())
                        .disabled(store.thinking)
                }
                if let note = m.note {
                    if let link = m.link {
                        Link(note, destination: link).font(.system(size: 11)).foregroundStyle(Palette.accent)
                    } else {
                        Text(note).font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                    }
                }
                if !m.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(m.actions, id: \.self) { a in
                            Button(store.label(for: a)) { store.perform(a, from: m.id) }
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Palette.surface2, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !m.recordedCycles.isEmpty {
                    Divider()
                    cycleVisualization(m.recordedCycles)
                }
                ForEach(m.comparisons.indices, id: \.self) { index in
                    Divider()
                    SymptomComparisonView(snapshot: m.comparisons[index])
                }
                ForEach(m.savedLogs) { result in
                    Divider()
                    savedEntries(result)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
            .shadow(color: Palette.berry.opacity(0.07), radius: 10, y: 4)
            .frame(maxWidth: 320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cycleVisualization(_ cycles: [ComparedCycle]) -> some View {
        let maximum = max(cycles.compactMap { cycle in
            cycle.nextStart.map { CycleStore.days($0, from: cycle.start) }
        }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Recorded cycles (\(cycles.count))").font(.headline)
            Text("Cycle length in days, measured between recorded period starts.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            ForEach(cycles) { cycle in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Started \(readableDate(cycle.start))")
                        .font(.subheadline.weight(.semibold))
                    if let next = cycle.nextStart {
                        let days = CycleStore.days(next, from: cycle.start)
                        HStack(spacing: 10) {
                            GeometryReader { geometry in
                                Capsule().fill(Palette.surface2)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Palette.accent.opacity(0.75))
                                            .frame(width: geometry.size.width * CGFloat(days) / CGFloat(maximum))
                                    }
                            }
                            .frame(height: 10)
                            Text("\(days) days").font(.caption).monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cycle starting \(readableDate(cycle.start)): \(days) days")
                    } else {
                        Label("Ongoing — final length not yet known", systemImage: "clock")
                            .font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    DisclosureGroup("Symptoms and saved entries") {
                        VStack(alignment: .leading, spacing: 8) {
                            let symptoms = Set(cycle.logs.flatMap(\.symptoms)).sorted()
                            if cycle.logs.isEmpty {
                                Text("No daily logs saved for this cycle")
                            } else if symptoms.isEmpty {
                                Text("No symptoms recorded.")
                            }
                            ForEach(symptoms, id: \.self) { symptom in
                                let count = Set(cycle.logs.filter { $0.symptoms.contains(symptom) }
                                    .map { CycleStore.cal.startOfDay(for: $0.date) }).count
                                Text("\(symptom): \(count) recorded \(count == 1 ? "day" : "days")")
                            }
                            ForEach(cycle.logs) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(readableDate(entry.date))
                                        .fontWeight(.medium)
                                    Text(entry.symptoms.isEmpty ? "No symptoms recorded" : entry.symptoms.joined(separator: ", "))
                                    if let pain = entry.pain { Text("Overall daily pain: \(pain)/10") }
                                    if !entry.note.isEmpty { Text(entry.note) }
                                    Button("View or edit entry") {
                                        store.selectedLogDate = entry.date
                                        store.showingLogPreview = true
                                        store.showLog = true
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.font(.caption).padding(.top, 6)
                    }
                    .font(.caption)
                    .tint(Palette.accent)
                }
                .padding(12)
                .background(Palette.surface2.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func readableDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year().locale(Locale(identifier: "en_US")))
    }

    private func savedEntries(_ result: SavedLogResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved entries").font(.headline)
            Text("\(readableDate(result.from)) – \(readableDate(result.to))")
                .font(.caption).foregroundStyle(Palette.inkSoft)
            if result.logs.isEmpty {
                Text("No saved entries in this date range.")
                    .font(.subheadline).foregroundStyle(Palette.inkSoft)
            } else {
                ForEach(result.logs) { log in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Symptoms: \(log.symptoms.isEmpty ? "None recorded" : log.symptoms.joined(separator: ", "))")
                            Text("Moods: \(log.moods.isEmpty ? "None recorded" : log.moods.joined(separator: ", "))")
                            Text("Flow: \(log.flow)")
                            Text(log.pain > 0 ? "Daily pain: \(log.pain)/10" : "Daily pain: 0 or not rated")
                            Text("Saved energy: \(log.energy)/5")
                            if !log.note.isEmpty { Text(log.note) }
                            Button("View or edit entry") {
                                store.selectedLogDate = log.date
                                store.showingLogPreview = true
                                store.showLog = true
                            }
                            .foregroundStyle(Palette.accent)
                        }
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    } label: {
                        Text(readableDate(log.date))
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(Palette.accent)
                }
            }
        }
    }
}

/// Stands in for an AI feature while the companion is off. Opens the Companion tab, which explains
/// what's shared before the user turns it on.
struct AIOffNotice: View {
    @Environment(CycleStore.self) private var store
    let feature: String

    var body: some View {
        Button { store.tab = .companion } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Please turn on the AI companion").font(.system(size: 13, weight: .semibold))
                    Text("for \(feature). Showing our standard picks for now.")
                        .font(.system(size: 12)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Palette.mist, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Companion tab")
    }
}
