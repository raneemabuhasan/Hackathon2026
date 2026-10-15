// swift-tools-version: 5.9
import PackageDescription

// Foundation-only tests; independent of the iOS app target.
let package = Package(
    name: "PetalComparison",
    products: [.library(name: "PetalComparison", targets: ["PetalComparison"])],
    targets: [
        .target(name: "PetalComparison", path: "Petal",
                exclude: ["CompanionView.swift", "ContentView.swift", "CycleStore.swift", "CycleView.swift",
                          "LogSheet.swift", "NourishView.swift", "PetalApp.swift", "Theme.swift",
                          "TodayView.swift", "SymptomComparisonView.swift", "PeriodHistoryView.swift"],
                sources: ["SymptomComparison.swift", "PersonalHistory.swift", "CyclePrediction.swift"]),
        .testTarget(name: "PetalComparisonTests", dependencies: ["PetalComparison"],
                    path: "ComparisonTests")
    ]
)
