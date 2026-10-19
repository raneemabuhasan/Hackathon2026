import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct PetalApp: App {
    @State private var auth: AuthModel

    init() {
        FirebaseApp.configure()
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
    @State private var store: CycleStore?
    /// Set by the widget's link. Held through sign-in and onboarding, then opens today's log.
    @State private var pendingLog = false

    private var canOpenLog: Bool {
        guard pendingLog, let store else { return false }
        return store.loaded && store.profile != nil && !store.showCycleSetup
    }

    var body: some View {
        Group {
            if !auth.ready {
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
    }

    private var splash: some View {
        Text("Petal")
            .font(.display(44))
            .italic()
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg.ignoresSafeArea())
    }
}
