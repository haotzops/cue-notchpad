// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CueNotchpad",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CueCore", targets: ["CueCore"]),
        .executable(name: "cue", targets: ["cue"]),
        .executable(name: "cue-host", targets: ["cue-host"]),
        .executable(name: "cue-core-tests", targets: ["CueCoreTests"]),
    ],
    targets: [
        .target(name: "CueCore", resources: [.process("Resources")]),
        .target(name: "CueApp", dependencies: ["CueCore"], resources: [.copy("../../Supporting/logo.svg")]),
        .executableTarget(name: "cue", dependencies: ["CueCore"]),
        .executableTarget(name: "cue-host", dependencies: ["CueApp", "CueCore"]),
        .executableTarget(name: "CueCoreTests", dependencies: ["CueCore"], path: "Tests/CueCoreTests"),
        .testTarget(name: "CueCoreXCTests", dependencies: ["CueCore", "CueApp"], path: "Tests/CueCoreXCTests"),
    ],
    swiftLanguageModes: [.v5]
)
