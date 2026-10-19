// swift-tools-version: 5.9
import PackageDescription

// Foundation-only tests; independent of the iOS app target.
let package = Package(
    name: "PetalComparison",
    products: [.library(name: "PetalComparison", targets: ["PetalComparison"])],
    targets: [
        .target(name: "PetalComparison", path: "Petal",
                exclude: ["Animations", "Assistant.swift", "AuthModel.swift", "CompanionView.swift", "ContentView.swift", "CycleStore.swift", "CycleView.swift", "GoogleService-Info.plist", "LogSheet.swift", "NourishView.swift", "OnboardingView.swift", "PeriodHistory.swift", "PetalApp.swift", "README_VALEN.txt", "Reminders.swift", "SettingsView.swift", "SignInView.swift", "SymptomComparisonView.swift", "Theme.swift", "TodayView.swift"],
                sources: ["SymptomComparison.swift"]),
        .testTarget(name: "PetalComparisonTests", dependencies: ["PetalComparison"],
                    path: "ComparisonTests")
    ]
)
