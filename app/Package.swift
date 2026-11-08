// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Optimizr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Optimizr", targets: ["Optimizr"]),
        .executable(name: "optimizr-scan", targets: ["OptimizrScan"]),
        .library(name: "OptimizrCore", targets: ["OptimizrCore"])
    ],
    targets: [
        .target(
            name: "OptimizrCore",
            path: "Sources/OptimizrCore"
        ),
        .executableTarget(
            name: "Optimizr",
            dependencies: ["OptimizrCore"],
            path: "Sources/Optimizr"
        ),
        .executableTarget(
            name: "OptimizrScan",
            dependencies: ["OptimizrCore"],
            path: "Sources/OptimizrScan"
        ),
        .testTarget(
            name: "OptimizrCoreTests",
            dependencies: ["OptimizrCore"],
            path: "Tests/OptimizrCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
