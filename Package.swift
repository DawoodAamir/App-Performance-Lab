// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PerformanceCore",
    products: [.library(name: "PerformanceCore", targets: ["PerformanceCore"])],
    targets: [
        .target(name: "PerformanceCore", path: "Sources/Core"),
        .testTarget(name: "PerformanceCoreTests", dependencies: ["PerformanceCore"], path: "Tests"),
    ])
