// swift-tools-version: 5.9
import PackageDescription

// The same Core sources and tests run on macOS without an iOS Simulator.
let package = Package(
    name: "JimmsBroCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "JimmsBroCore", targets: ["JimmsBro"])],
    targets: [
        .target(name: "JimmsBro", path: "JimmsBro", sources: ["Core", "Store"]),
        .testTarget(
            name: "JimmsBroTests", dependencies: ["JimmsBro"], path: ".",
            exclude: ["JimmsBro", "JimmsBro.xcodeproj", "docs", "schema", "tools", "build",
                      "AGENTS.md", "CLAUDE.md", "README.md", "HANDOFF_BUNDLE.md",
                      "JimmsBro-design-package.zip", "JimmsBroTests/ProjectSkeletonTests.swift"],
            sources: ["JimmsBroTests/FixtureLoader.swift", "JimmsBroTests/CoreTestSupport.swift",
                      "JimmsBroTests/ImportTests.swift", "JimmsBroTests/StepsAndEngineTests.swift",
                      "JimmsBroTests/PrefillAndStatsTests.swift", "JimmsBroTests/LibraryCalendarPromptTests.swift",
                      "JimmsBroTests/StoreTests.swift", "JimmsBroTests/SettingsAndHomeTests.swift", "JimmsBroTests/WorkoutTests.swift", "JimmsBroTests/HistoryTests.swift", "JimmsBroTests/SettingsPolishTests.swift",
                      "JimmsBroTests/WorkoutScreenTests.swift",
                      "JimmsBroTests/HomeAndAddPlanTests.swift",
                      "JimmsBroTests/SummaryAndVisualTests.swift",
                      "JimmsBroTests/DeferExerciseTests.swift",
                      "JimmsBroTests/PlanEditTests.swift",
                      "JimmsBroTests/RecordsAndChartTests.swift",
                      "JimmsBroTests/RestoreTests.swift"],
            resources: [.copy("examples")]
        )
    ]
)
