// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HouseCleaning",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HouseCleaning", targets: ["HouseCleaning"])
    ],
    targets: [
        .target(name: "HouseCleaningCore"),
        .executableTarget(name: "HouseCleaning", dependencies: ["HouseCleaningCore"]),
        .testTarget(name: "HouseCleaningCoreTests", dependencies: ["HouseCleaningCore"]),
    ]
)
