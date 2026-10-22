import SwiftUI
import Lottie
import FirebaseCore
import GoogleSignIn

@main
struct PetalApp: App {
    @State private var auth: AuthModel

    init() {
        FirebaseApp.configure()
        ReminderNotifications.showWhileOpen()
        _auth = State(initialValue: AuthModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .preferredColorScheme(.light)
        }
    }
}

/// Signed out → SignInView. Signed in without a profile → OnboardingView. Otherwise the app.
struct RootView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: CycleStore?
    /// Set by the widget's link. Held through sign-in and onboarding, then opens today's log.
    @State private var pendingLog = false

    private var canOpenLog: Bool {
        guard pendingLog, let store else { return false }
        return store.loaded && store.profile != nil && !store.showCycleSetup
    }
    @State private var showingLaunchAnimation = true

    var body: some View {
        Group {
            if showingLaunchAnimation {
                launchSplash
            } else if !auth.ready {
                splash
            } else if auth.user == nil {
                SignInView()
            } else if let store, store.loaded {
                Group {
                    if store.profile == nil { OnboardingView() } else { ContentView() }
                }
                .environment(store)
            } else {
                splash
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .animation(.easeOut(duration: 0.25), value: showingLaunchAnimation)
        .animation(.easeOut(duration: 0.25), value: auth.user?.uid)
        .animation(.easeOut(duration: 0.25), value: store?.profile == nil)
        .onChange(of: auth.user?.uid, initial: true) { _, uid in
            store?.stop()
            store = uid.map { CycleStore(uid: $0) }
        }
        .onOpenURL { url in
            if DeepLink(url) == .log { pendingLog = true } else { GIDSignIn.sharedInstance.handle(url) }
        }
        .onChange(of: canOpenLog, initial: true) { _, ready in
            guard ready, let store else { return }
            pendingLog = false
            store.selectedLogDate = nil
            store.showLog = true
                                                 }
        .task {
            // A short intro plays once per app launch, independently of Firebase loading.
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 2.9))
            showingLaunchAnimation = false
        }
    }

    private var launchSplash: some View {
        Group {
            if reduceMotion {
                splash
            } else {
                GeometryReader { geometry in
                    LottieView(animation: .named("sync-animation"))
                        // The supplied animation contains 11 seconds, with a long end hold.
                        // Play the complete shorter logo motion in ~2.9 seconds, then show the app.
                        .playing(.fromFrame(0, toFrame: 320, loopMode: .playOnce))
                        .configure { $0.animationSpeed = 2.3 }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Compact wordmark, centered on any iPhone screen size.
                        .frame(width: min(380, geometry.size.width * 0.95))
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                }
                .background(Color.white.ignoresSafeArea())
                .ignoresSafeArea()
                .accessibilityLabel("Sync")
            }
        }
    }

    private var splash: some View {
        Text("Sync")
            .font(.display(44))
            .italic()
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg.ignoresSafeArea())
    }
}
