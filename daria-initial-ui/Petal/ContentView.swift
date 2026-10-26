import SwiftUI

// Optional in-app overlay; it doesn't enable AI or affect chat permissions.
// Drag starts only after a hold so ordinary scrolling and tapping keep working.
// In-app floating robot: touch reactions and animation-free placement.
// Dragging runs through @GestureState; no repeating movement animation or disk writes during drag.
@MainActor
private struct FloatingRobotShortcut: View {
    let size: CGSize
    let isEditing: Bool
    let onOpenCompanion: () -> Void
    let onFinishEditing: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sync.floatingRobot.x") private var savedX = 0.85
    @AppStorage("sync.floatingRobot.y") private var savedY = 0.55
    @AppStorage("sync.companion.character") private var selectedCharacterRaw = "robot"
    private var selectedCharacter: CompanionCharacter {
        CompanionCharacter(rawValue: selectedCharacterRaw) ?? .robot
    }
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var sleeping = false
    @State private var blinking = false
    @State private var wiggling = false
    @State private var reaction: Reaction = .idle
    @State private var activityID = 0
    @State private var reactionID = 0

    private enum Reaction {
        case idle, happy, curious
    }

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

    private var dragPoint: CGPoint {
        constrain(CGPoint(
            x: restingPoint.x + dragTranslation.width,
            y: restingPoint.y + dragTranslation.height
        ))
    }

    private var imageName: String {
        if isEditing { return selectedCharacter.asset("Idle") }
        switch reaction {
        case .happy: return selectedCharacter.asset("Happy")
        case .curious: return selectedCharacter.asset("Thinking")
        case .idle:
            if sleeping { return selectedCharacter.asset("Sleep") }
            if wiggling && selectedCharacter != .robot { return selectedCharacter.asset("Wiggle") }
            return selectedCharacter.asset(blinking ? "Blink" : "Idle")
        }
    }

    private var robotImage: some View {
        Image(imageName)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: 74, height: 84)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sleeping && !isEditing ? "Sleeping \(selectedCharacter.name) companion" : "\(selectedCharacter.name) companion")
            .accessibilityHint(isEditing
                ? "Drag the companion to a new position"
                : "Double tap to open Companion. Tap for a smile, or hold for a curious reaction")
    }

    private func wake() {
        sleeping = false
        blinking = false
        wiggling = false
        activityID += 1
    }

    private func react(_ next: Reaction) {
        wake()
        reaction = next
        reactionID += 1
    }

    // A double tap wins over a single tap, so opening the chat never also plays the tap reaction.
    private var taps: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { result in
                switch result {
                case .first:
                    wake()
                    onOpenCompanion()
                case .second:
                    react(.happy)
                }
            }
    }

    // The gesture lives on the stationary canvas, not the moving sprite.
    // A fixed coordinate space eliminates feedback/jitter as the image moves.
    // Persist only once, on release; no view animations during placement.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("floatingRobotDragCanvas"))
            .updating($dragTranslation) { value, translation, transaction in
                // Only begin a drag when the touch starts on the robot.
                guard abs(value.startLocation.x - restingPoint.x) <= 48,
                      abs(value.startLocation.y - restingPoint.y) <= 52 else { return }
                transaction.animation = nil
                transaction.disablesAnimations = true
                translation = value.translation
            }
            .onEnded { value in
                guard abs(value.startLocation.x - restingPoint.x) <= 48,
                      abs(value.startLocation.y - restingPoint.y) <= 52 else { return }
                let point = constrain(CGPoint(
                    x: restingPoint.x + value.translation.width,
                    y: restingPoint.y + value.translation.height
                ))
                var noAnimation = Transaction(animation: nil)
                noAnimation.disablesAnimations = true
                withTransaction(noAnimation) {
                    savedX = Double(point.x / max(1, size.width))
                    savedY = Double(point.y / max(1, size.height))
                }
                wake()
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isEditing {
                // Stationary full-screen hit surface: the gesture never moves.
                Color.black.opacity(0.05)
                    .contentShape(Rectangle())
                    .gesture(moveGesture)

                // Visual only during editing. The image cannot intercept touches.
                robotImage
                    .position(dragPoint)
                    .allowsHitTesting(false)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            } else {
                robotImage
                    // A quick happy hop only during tap reactions; never while positioning.
                    .offset(y: reaction == .happy && !reduceMotion && selectedCharacter != .bear && selectedCharacter != .kitten ? -5 : 0)
                    .animation(.spring(duration: 0.22), value: reaction)
                    .overlay(alignment: .topTrailing) {
                        if reaction == .happy {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.accent)
                                .offset(x: 7, y: -8)
                                .allowsHitTesting(false)
                        } else if reaction == .curious {
                            Text("…")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .offset(x: 7, y: -9)
                                .allowsHitTesting(false)
                        }
                    }
                    .gesture(taps)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.55).onEnded { succeeded in
                            if succeeded { react(.curious) }
                        }
                    )
                    .position(restingPoint)
            }

            if isEditing {
                HStack(spacing: 12) {
                    Label("Drag companion to move", systemImage: "hand.draw")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("Done", action: onFinishEditing)
                        .font(.system(size: 14, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "floatingRobotDragCanvas")
        .onChange(of: isEditing) { _, _ in
            reaction = .idle
            reactionID += 1
            wake()
        }
        // A short-lived reaction returns to idle. Only the expression changes, never the position.
        .task(id: reactionID) {
            guard reaction != .idle else { return }
            do {
                try await Task.sleep(for: .seconds(reaction == .happy ? 1.1 : 1.8))
            } catch { return }
            reaction = .idle
        }
        // Occasional eye blinks, then sleep. No perpetual floating animation to interfere with dragging.
        .task(id: activityID) {
            sleeping = false
            blinking = false
            wiggling = false
            guard !isEditing, !reduceMotion else { return }
            for cycle in 0..<2 {
                do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
                guard reaction == .idle else { continue }
                if selectedCharacter != .robot && cycle == 1 {
                    wiggling = true
                    do { try await Task.sleep(for: .milliseconds(480)) } catch { return }
                    wiggling = false
                } else {
                    blinking = true
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    blinking = false
                }
            }
            do { try await Task.sleep(for: .seconds(4.7)) } catch { return }
            if !Task.isCancelled, reaction == .idle { sleeping = true }
        }
    }
}

// Shared transient setting between Settings sheet and ContentView.
@MainActor @Observable
final class FloatingRobotPlacement {
    static let shared = FloatingRobotPlacement()
    var isEditing = false
}

@MainActor
struct ContentView: View {
      @Environment(CycleStore.self) private var store
      @AppStorage("sync.floatingRobot.enabled") private var floatingRobotEnabled = false
      @State private var placement = FloatingRobotPlacement.shared
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
            if floatingRobotEnabled && store.aiEnabled && store.tab != .companion {
                GeometryReader { viewport in
                    FloatingRobotShortcut(
                        size: viewport.size,
                        isEditing: placement.isEditing,
                        onOpenCompanion: { store.tab = .companion },
                        onFinishEditing: { placement.isEditing = false }
                    )
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
        .onChange(of: store.aiEnabled) { _, enabled in
            if !enabled {
                floatingRobotEnabled = false
                placement.isEditing = false
            }
        }
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

