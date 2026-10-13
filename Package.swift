// swift-tools-version: 6.0
import PackageDescription

// Host isolation is structural: TattleCore is pure logic behind protocols, and
// the test target depends on it ONLY. Nothing in the tests can link
// TattleSystem, so a test can never touch real Core Audio, sysctl or kill(2).
let package = Package(
    name: "Tattle",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Tattle", targets: ["TattleApp"]),
        .executable(name: "tattle-bridge", targets: ["TattleBridge"]),
    ],
    dependencies: [
        // In-app updates. Linked by the app target only: TattleCore (and so every test) never sees it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .target(name: "TattleCore"),
        .target(
            name: "TattleSystem",
            dependencies: ["TattleCore"],
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "TattleApp",
            dependencies: ["TattleCore", "TattleSystem", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .executableTarget(name: "tattle-scan", dependencies: ["TattleCore", "TattleSystem"], path: "Sources/TattleScan"),
        .executableTarget(name: "TattleBridge", dependencies: ["TattleCore", "TattleSystem"]),
        .testTarget(name: "TattleCoreTests", dependencies: ["TattleCore"]),
    ]
)
