import SwiftUI

/// Ready to embed in Profile once that screen is integrated.
@MainActor
struct DataManagementSection: View {
    @Environment(CycleStore.self) private var store
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your data")
            Text("Logs stay on this device. Nothing is shared or sold. You can erase everything at any time.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
            if confirmingDelete {
                Text("This erases every log and preference on this device. It can't be undone.")
                    .font(.system(size: 13))
                HStack {
                    outlineButton("Erase everything") { store.deleteAllData(); confirmingDelete = false }
                    Button("Keep my data") { confirmingDelete = false }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Palette.surface2, in: Capsule())
                        .buttonStyle(.plain)
                }
            } else {
                outlineButton("Delete all my data") { confirmingDelete = true }
            }
        }
        .card()
        .animation(.easeOut(duration: 0.2), value: confirmingDelete)
    }

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(Capsule().stroke(Palette.rose.opacity(0.3)))
            .buttonStyle(.plain)
    }
}
