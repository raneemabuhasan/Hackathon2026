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
    /// Bumped on each sign-in so the logo plays through once before onboarding or the app fades in.
    @State private var introRun = 0

    /// Waiting on Firebase: auth state, or a signed-in user's profile.
    private var loading: Bool { !auth.ready || (auth.user != nil && store?.loaded != true) }

    var body: some View {
        Group {
            if let error = store?.profileError, store?.loaded != true {
                loadError(error)
            } else if showingLaunchAnimation || loading || auth.deletingAccount {
                launchSplash
            } else if auth.user == nil {
                SignInView()
            } else if let store, store.loaded {
                Group {
                    if store.profile == nil { OnboardingView() } else { ContentView() }
                }
                .environment(store)
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .animation(.easeOut(duration: 0.25), value: showingLaunchAnimation)
        .animation(.easeOut(duration: 0.25), value: auth.user?.uid)
        .animation(.easeOut(duration: 0.25), value: store?.profile == nil)
        // Crossfade from the logo to whatever loads next (onboarding or the app) instead of cutting.
        .animation(.easeInOut(duration: 0.4), value: loading)
        .onChange(of: auth.user?.uid, initial: true) { old, uid in
            if old == nil, uid != nil, auth.ready, !showingLaunchAnimation {
                showingLaunchAnimation = true
                introRun += 1
            }
            store?.stop()
            // The palette belongs to the account: once nobody is signed in (sign-out or account deletion),
            // drop back to the default so the next person doesn't inherit it.
            if uid == nil { PalettePreferences.shared.theme = .blush }
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
        .task(id: introRun) {
            // A short intro plays once per app launch and after sign-in, independently of Firebase loading.
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
                .overlay(alignment: .bottom) {
                    // Only once the intro has finished and we're still waiting on Firebase.
                    if !showingLaunchAnimation {
                        ProgressView().tint(Palette.accent).padding(.bottom, 80)
                    }
                }
                .background(Color(hex: 0xFAF0E6).ignoresSafeArea())
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
            .background(Color(hex: 0xFAF0E6).ignoresSafeArea())
    }

    private func loadError(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("Sync").font(.display(44)).italic().foregroundStyle(Palette.accent)
            Text(message).font(.system(size: 15)).foregroundStyle(Palette.inkSoft)
            Text("Check your connection and try again.").font(.system(size: 13)).foregroundStyle(Palette.inkFaint)
            Button("Sign out") { auth.signOut() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}
