import SwiftUI

// Optional in-app overlay; it doesn't enable AI or affect chat permissions.
// Drag starts only after a hold so ordinary scrolling and tapping keep working.
@MainActor
private struct FloatingRobotShortcut: View {
    let size: CGSize
    let onOpenCompanion: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sync.floatingRobot.x") private var savedX = 0.85
    @AppStorage("sync.floatingRobot.y") private var savedY = 0.55
    @GestureState private var dragOffset: CGSize = .zero
    @State private var hovering = false
    @State private var sleeping = false
    @State private var wakeNumber = 0

    private let margin: CGFloat = 43

    private func constrain(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(margin, point.x), max(margin, size.width - margin)),
            y: min(max(margin, point.y), max(margin, size.height - margin))
        )
    }

    private var restingPoint: CGPoint {
        constrain(CGPoint(x: size.width * CGFloat(savedX), y: size.height * CGFloat(savedY)))
    }

    private var displayedPoint: CGPoint {
        constrain(CGPoint(x: restingPoint.x + dragOffset.width,
                          y: restingPoint.y + dragOffset.height))
    }

    private func wake() {
        sleeping = false
        wakeNumber += 1
    }

    private var holdAndMove: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($dragOffset) { value, state, _ in
                if case .second(true, let drag?) = value {
                    state = drag.translation
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                let point = constrain(CGPoint(x: restingPoint.x + drag.translation.width,
                                              y: restingPoint.y + drag.translation.height))
                savedX = Double(point.x / max(1, size.width))
                savedY = Double(point.y / max(1, size.height))
                wake()
            }
    }

    var body: some View {
        Image(sleeping ? "CompanionRobotSleep" : "CompanionRobotIdle")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: 74, height: 84)
            .offset(y: reduceMotion || sleeping ? 0 : (hovering ? -3 : 2))
            .contentShape(Rectangle())
            .onTapGesture {
                wake()
                onOpenCompanion()
            }
            .simultaneousGesture(holdAndMove)
            .position(displayedPoint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sleeping ? "Sleeping robot companion" : "Robot companion")
            .accessibilityHint("Tap to open Companion. Hold and drag to move.")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    hovering = true
                }
            }
            .task(id: wakeNumber) {
                sleeping = false
                do { try await Task.sleep(for: .seconds(14)) } catch { return }
                if !Task.isCancelled { sleeping = true }
            }
    }
}

@MainActor
struct ContentView: View {
      @Environment(CycleStore.self) private var store
      @AppStorage("sync.floatingRobot.enabled") private var floatingRobotEnabled = false
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

            // Only on in-app pages; never covers the chat input or onboarding.
            if floatingRobotEnabled && store.tab != .companion {
                GeometryReader { viewport in
                    FloatingRobotShortcut(size: viewport.size) {
                        store.tab = .companion
                    }
                }
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar()
                .background {
                    Rectangle()
                        .fill(.thickMaterial)
                        .overlay(Palette.bg.opacity(0.45))
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.24),
                                .init(color: .white, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                        .padding(.top, -24)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
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
        .sheet(isPresented: $store.showCycleSetup) {
            CycleSetupView()
                .environment(store)
                .presentationCornerRadius(32)
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
    @Namespace private var activeTab

    var body: some View {
        HStack(spacing: 0) {
            item(.today, "Today", "circle.circle")
            item(.cycle, "Calendar", "calendar")
            Button {
                store.showingLogPreview = false
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
                // Symbols differ in height; a fixed slot keeps every label on the same line.
                Image(systemName: icon).font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .symbolVariant(selected ? .fill : .none)
                    .frame(height: 24)
                Text(title).font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Palette.accent : Palette.inkFaint)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                // One pill that slides to whichever tab is active.
                if selected {
                    Capsule().fill(Palette.mist).matchedGeometryEffect(id: "pill", in: activeTab)
                }
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.spring(duration: 0.3, bounce: 0.2), value: store.tab)
    }
}

