// swift-tools-version: 5.9
import PackageDescription

// The same Core sources and tests run on macOS without an iOS Simulator.
let package = Package(
    name: "JimmsBroCore",
    // macOS 14, not 13: `AppModel` is `@Observable`, and the Observation module is only
    // available from macOS 14. Declaring 13 made `swift test` fail to compile from the day
    // AppModel landed, while README went on claiming the route worked.
    platforms: [.macOS(.v14), .iOS(.v17)],
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
                      "JimmsBroTests/RestoreTests.swift",
                      "JimmsBroTests/DefectFixesTests.swift",
                      "JimmsBroTests/StoreMigrationTests.swift",
                      "JimmsBroTests/PromptPinningTests.swift",
                      "JimmsBroTests/WarmUpAndTransitionTests.swift",
                      "JimmsBroTests/SuggestionTests.swift",
                      "JimmsBroTests/ScheduleAnchorTests.swift",
                      "JimmsBroTests/MetricsTests.swift",
                      "JimmsBroTests/ActivityTests.swift",
                      "JimmsBroTests/ChangeExerciseTests.swift",
                      "JimmsBroTests/JSONEditTests.swift",
                      "JimmsBroTests/HistoryCSVTests.swift",
                      "JimmsBroTests/ProgressionTests.swift"],
            resources: [.copy("examples")]
        )
    ]
)
