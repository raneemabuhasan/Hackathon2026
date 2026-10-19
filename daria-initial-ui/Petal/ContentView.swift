import SwiftUI

@MainActor
struct ContentView: View {
      @Environment(CycleStore.self) private var store
      @Environment(\.scenePhase) private var scenePhase 

    var body: some View {
        @Bindable var store = store

        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            Group {
                switch store.tab {
                case .today: TodayView()
                case .cycle: CycleView()
                case .nourish: NourishView()
                case .companion: CompanionView()
                }
            }
            .transition(.opacity)

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar()
        }
        .animation(.easeOut(duration: 0.2), value: store.tab)
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.cream)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Palette.ink, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 4)
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .sheet(isPresented: $store.showLog) {
            LogSheet()
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
        .environment(store)
        .fullScreenCover(isPresented: $store.showCycleSetup) {
            CycleSetupView().environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.today = Calendar.current.startOfDay(for: Date()) }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
    }
}

@MainActor
struct TabBar: View {
    @Environment(CycleStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            item(.today, "Today", "circle.circle")
            item(.cycle, "Calendar", "calendar")
            Button {
                store.selectedLogDate = store.tab == .cycle ? store.selectedCalendarDate ?? store.today : nil
                store.showLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Palette.accent, in: Circle())
                    .shadow(color: Palette.rose.opacity(0.4), radius: 10, y: 6)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(store.tab == .cycle ? "Log selected date" : "Log today")
            .disabled(store.tab == .cycle && (store.selectedCalendarDate ?? store.today) > store.today)
            item(.nourish, "Nourish", "leaf")
            item(.companion, "Companion", "sparkles")
        }
        .padding(.horizontal, 6)
        .frame(height: 70)
        .background(Palette.surface, in: Capsule())
        .shadow(color: Palette.wine.opacity(0.14), radius: 18, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func item(_ tab: Tab, _ title: String, _ icon: String) -> some View {
        let selected = store.tab == tab
        return Button { store.tab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19, weight: selected ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? Palette.accent : Palette.inkFaint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

