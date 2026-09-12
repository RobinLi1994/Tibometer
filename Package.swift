// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tibometer",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tibometer", targets: ["Tibometer"]),
        .executable(name: "tibometer-probe", targets: ["TibometerProbe"]),
        .executable(name: "tibometer-tests", targets: ["TibometerTests"]),
    ],
    targets: [
        .target(name: "TibometerCore", resources: [.process("Resources")]),
        .executableTarget(name: "Tibometer", dependencies: ["TibometerCore"], resources: [.process("Resources")]),
        .executableTarget(name: "TibometerProbe", dependencies: ["TibometerCore"]),
        .executableTarget(name: "TibometerTests", dependencies: ["TibometerCore"], path: "Tests/TibometerCoreTests"),
    ]
)
