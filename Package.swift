// swift-tools-version:5.9
import PackageDescription

// Unit tests for PlayCar's platform-independent logic: run `swift test` on a Mac
// (no simulator or device needed). The app itself is built from
// PlayCarIOS.xcodeproj — this package only compiles the listed files for tests.
let package = Package(
    name: "PlayCarCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(
            name: "PlayCarCore",
            path: "PlayCarIOS/Services",
            // iOS-only services (UIKit, AVFoundation, CallKit, MediaPlayer…).
            exclude: [
                "CallStore.swift",
                "ContactsStore.swift",
                "DoNotDisturbController.swift",
                "LocationManager.swift",
                "MusicPlayerManager.swift",
                "NavigationStore.swift",
                "SearchService.swift",
                "TelemetryStore.swift",
            ],
            sources: [
                "FavoritesStore.swift",
                "FocusShortcut.swift",
                "Maneuver.swift",
                "NavFormat.swift",
                "RecentDestinationsStore.swift",
                "RouteGeometry.swift",
                "SpeedLimitStore.swift",
                "TripStore.swift",
            ]
        ),
        .testTarget(
            name: "PlayCarCoreTests",
            dependencies: ["PlayCarCore"],
            path: "Tests/PlayCarCoreTests"
        ),
    ]
)
