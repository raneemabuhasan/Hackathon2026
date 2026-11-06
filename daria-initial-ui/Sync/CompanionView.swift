import SwiftUI

// One selected visual character; both share Sync's existing AI and floating controls.
enum CompanionCharacter: String, CaseIterable, Identifiable {
    case robot, bunny, kitten, bear, frog
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    func asset(_ state: String) -> String { "Companion" + name + state }
}

// The default robot is a visual companion. AI logic stays inside CycleStore.
// Keep this in CompanionView.swift to avoid changing the Xcode project file.
@MainActor
struct PixelRobotCompanion: View {
    var thinking = false
    var width: CGFloat = 108
    var pacing = false
    var character: CompanionCharacter = .robot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false
    @State private var smiling = false

    private var imageName: String {
        if smiling { return character.asset("Happy") }
        if thinking { return character.asset("Thinking") }
        if blink { return character.asset("Blink") }
        return character.asset("Idle")
    }

    var body: some View {
        Button { smiling = true } label: {
            TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Move within a dedicated header lane, never on top of the bell.
                // Rounded whole-point offsets keep the pixel artwork sharp.
                let distance: Double = pacing ? (thinking ? 17 : 9) : 0
                let horizontal = reduceMotion ? 0 : (sin(t * (thinking ? 2.0 : 0.8)) * distance).rounded()
                let vertical = reduceMotion ? 0 : (cos(t * (thinking ? 8.0 : 2.1)) * (pacing ? 1.5 : 2)).rounded()
                let wiggle = (character != .robot) && !reduceMotion && !smiling && !thinking && !blink
                    && Int(t * 1.3).isMultiple(of: 17)
                (smiling ? CompanionPageSmile.image(for: character) : Image(wiggle ? character.asset("Wiggle") : imageName))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: width, height: width * 1.23)
                    .offset(x: CGFloat(horizontal), y: CGFloat(vertical))
                    .frame(width: pacing ? 90 : width, height: width * 1.23)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(character.name) companion")
        .accessibilityHint("Tap to make your companion smile")
        .task(id: thinking) {
            blink = false
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3.8)) } catch { return }
                if thinking { continue }
                blink = true
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                blink = false
            }
        }
        .task(id: smiling) {
            guard smiling else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            smiling = false
        }
    }
}

// Companion-page smiles omit decorations; floating Happy assets stay untouched.
@MainActor
private enum CompanionPageSmile {
    private static let images: [String: UIImage] = {
        let decorations: [(String, CGRect)] = [
            ("Kitten", CGRect(x: 219, y: 47, width: 27, height: 25)),
            ("Bear", CGRect(x: 218, y: 37, width: 22, height: 20)),
            ("Frog", CGRect(x: 1048, y: 183, width: 143, height: 138))
        ]
        var result: [String: UIImage] = [:]
        for (name, decoration) in decorations {
            guard let source = UIImage(named: "Companion" + name + "Happy"),
                  let cgImage = source.cgImage else { continue }
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            result[name] = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .none
                UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
                context.cgContext.clear(decoration)
                if name == "Bear" {
                    // Clear the heart tip without touching the seated bear's ear.
                    context.cgContext.clear(CGRect(x: 224, y: 57, width: 16, height: 3))
                }
            }
        }
        return result
    }()

    static func image(for character: CompanionCharacter) -> Image {
        if let smile = images[character.name] { return Image(uiImage: smile) }
        return Image(character.asset("Happy"))
    }
}

@MainActor
struct CompanionView: View {
    @Environment(CycleStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var showCharacterPicker = false
    @AppStorage("sync.companion.character") private var selectedCharacterRaw = "robot"
    private var selectedCharacter: CompanionCharacter {
        CompanionCharacter(rawValue: selectedCharacterRaw) ?? .robot
    }

    private var canSend: Bool {
        store.aiEnabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.thinking
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Eyebrow(text: "Companion")
                    Spacer(minLength: 4)
                    // Keep the selected character visible in the conversation header.
                    if !store.messages.isEmpty {
                        PixelRobotCompanion(thinking: store.thinking, width: 44, pacing: true,
                                            character: selectedCharacter)
                    }
                    Button { showCharacterPicker = true } label: {
                        Image(systemName: "pawprint")
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.inkSoft)
                    .accessibilityLabel("Choose companion character")
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)

                if !store.aiEnabled {
                    ScrollView { aiOffCard.padding(24) }
                } else if store.messages.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 28)
                            VStack(spacing: 24) {
                                PixelRobotCompanion(thinking: store.thinking, width: 104,
                                                    character: selectedCharacter)
                                VStack(spacing: 10) {
                                    DisplayTitle(before: "What’s on\n", accent: "your mind?", size: 34)
                                        .multilineTextAlignment(.center)
                                    Text("A little support for your cycle.")
                                        .font(.subheadline).foregroundStyle(Palette.inkSoft)
                                }
                                composerField
                                VStack(spacing: 4) {
                                    suggestion("Find a little comfort", question: "Help me feel better with cramps")
                                    suggestion("What could I eat today?", question: "What should I eat today?")
                                    suggestion("Help me understand my cycle", question: "When is my next period?")
                                }
                            }
                            Spacer(minLength: 48)
                            disclaimer
                                .padding(.bottom, 16)
                        }
                        .padding(.horizontal, 24)
                        .frame(minHeight: max(0, geometry.size.height - 68))
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                } else {
                    conversation
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            VStack(spacing: 8) { composerField; disclaimer }
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(Palette.bg)
                        }
                }
            }
        }
        .sheet(isPresented: $showCharacterPicker) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose your companion")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("The same helpful AI, with a different little friend. Your choice also changes the floating companion.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkSoft)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                        ForEach(CompanionCharacter.allCases) { candidate in
                            Button {
                                selectedCharacterRaw = candidate.rawValue
                                showCharacterPicker = false
                            } label: {
                                VStack(spacing: 8) {
                                    Image(candidate.asset("Idle"))
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .frame(width: 98, height: 110)
                                    Text(candidate.name)
                                        .font(.system(size: 15, weight: .semibold))
                                    Image(systemName: selectedCharacter == candidate ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedCharacter == candidate ? Palette.accent : Palette.inkFaint)
                                }
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 170)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(selectedCharacter == candidate ? Palette.accent : Palette.line,
                                                  lineWidth: selectedCharacter == candidate ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(candidate.name) companion")
                            .accessibilityAddTraits(selectedCharacter == candidate ? .isSelected : [])
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground(Palette.bg)
        }
    }

    private func suggestion(_ title: String, question: String) -> some View {
        Button {
            draft = question
            focused = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Ellipse()
                        .fill(Palette.blush)
                        .frame(width: 8, height: 15)
                        .rotationEffect(.degrees(-38))
                        .offset(x: -5, y: -2)
                    Ellipse()
                        .fill(Palette.petal)
                        .frame(width: 8, height: 15)
                        .rotationEffect(.degrees(38))
                        .offset(x: 4, y: -2)
                    Ellipse()
                        .fill(Palette.secondaryAccent.opacity(0.6))
                        .frame(width: 6, height: 11)
                        .rotationEffect(.degrees(65))
                        .offset(x: 1, y: 5)
                }
                .frame(width: 28, height: 30)
                .accessibilityHidden(true)
                Text(title).font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
            }
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 8).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds a suggested question to your draft")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(store.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if store.thinking {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.secondaryAccent)
                            Text("Thinking with you…")
                                .font(.subheadline).foregroundStyle(Palette.inkSoft)
                            Spacer()
                        }
                        .padding(16)
                        .accessibilityLabel("Companion is preparing a reply")
                    }
                    Color.clear.frame(height: 1).id("conversationBottom")
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
            .onChange(of: store.messages.count) { scrollToBottom(proxy) }
            .onChange(of: store.thinking) { scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private var disclaimer: some View {
        Text("AI companion · Wellness support, not medical advice")
            .font(.system(size: 10))
            .foregroundStyle(Palette.inkFaint)
            .multilineTextAlignment(.center)
    }

    private var composerField: some View {
            HStack(alignment: .bottom, spacing: 8) {
                // Keep keyboard input independent of the animated header.
                TextField("Ask your companion…", text: $draft)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .font(.system(size: 16))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.vertical, 12)
                    .accessibilityLabel("Message to Companion")
                if focused {
                    Button { focused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss keyboard")
                }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(canSend ? Color.white : Palette.inkFaint)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Palette.accent : Palette.secondarySurface, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.line))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversationBottom", anchor: .bottom) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        store.send(text)
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
