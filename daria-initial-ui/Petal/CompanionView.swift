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

                FlowLayout {
                    ForEach(prompts, id: \.self) { p in
                        Chip(label: p, selected: false, small: true) { store.send(p) }
                    }
                }

                VStack(spacing: 10) {
                    bubble(store.greeting)
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
            .onChange(of: store.messages.count) {
                if let last = store.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                TextField("Ask or set a reminder…", text: $draft)
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
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .background(Palette.surface, in: Capsule())
            .shadow(color: Palette.berry.opacity(0.1), radius: 12, y: 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
                Text(m.text).font(.system(size: 14))
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
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
            .shadow(color: Palette.berry.opacity(0.07), radius: 10, y: 4)
            .frame(maxWidth: 320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
