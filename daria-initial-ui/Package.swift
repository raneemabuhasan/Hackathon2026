// swift-tools-version: 5.9
import PackageDescription

// Foundation-only tests; independent of the iOS app target.
let package = Package(
    name: "SyncComparison",
    platforms: [.macOS(.v12)],
    products: [.library(name: "SyncComparison", targets: ["SyncComparison"])],
    targets: [
        .target(name: "SyncComparison", path: "Sync",
                exclude: ["Animations", "DeepLink.swift", "CompanionPrompt.swift", "Assistant.swift", "AuthModel.swift", "CompanionView.swift", "ContentView.swift", "CycleStore.swift", "CycleView.swift", "GoogleService-Info.plist", "LogSheet.swift", "NourishView.swift", "OnboardingView.swift", "SyncApp.swift", "README_VALEN.txt", "Reminders.swift", "SettingsView.swift", "SignInView.swift", "SymptomComparisonView.swift", "Theme.swift", "TodayView.swift"],
                sources: ["SymptomComparison.swift", "PeriodHistory.swift", "PasswordRequirement.swift", "EducationLibrary.swift", "CompanionLogging.swift", "CompanionContracts.swift", "CycleForecast.swift"],
                resources: [.process("Education")],
                swiftSettings: [.define("SYNC_EDUCATION_PACKAGE")]),
        .testTarget(name: "SyncComparisonTests", dependencies: ["SyncComparison"],
                    path: "ComparisonTests")
    ]
)
