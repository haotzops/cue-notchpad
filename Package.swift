// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CueNotepad",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CueCore", targets: ["CueCore"]),
        .executable(name: "cue", targets: ["cue"]),
        .executable(name: "cue-core-tests", targets: ["CueCoreTests"]),
    ],
    targets: [
        .target(
            name: "CueCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "cue",
            dependencies: ["CueCore"]
        ),
        .executableTarget(
            name: "CueCoreTests",
            dependencies: ["CueCore"],
            path: "Tests/CueCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
