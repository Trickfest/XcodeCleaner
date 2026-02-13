// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XcodeCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "XcodeInventoryCore",
            targets: ["XcodeInventoryCore"]
        ),
        .executable(
            name: "xcodecleaner-cli",
            targets: ["XcodeCleanerCLI"]
        ),
        .executable(
            name: "XcodeCleanerApp",
            targets: ["XcodeCleanerApp"]
        )
    ],
    targets: [
        .target(
            name: "XcodeInventoryCore"
        ),
        .executableTarget(
            name: "XcodeCleanerCLI",
            dependencies: ["XcodeInventoryCore"]
        ),
        .executableTarget(
            name: "XcodeCleanerApp",
            dependencies: ["XcodeInventoryCore"]
        ),
        .testTarget(
            name: "XcodeInventoryCoreTests",
            dependencies: ["XcodeInventoryCore"]
        ),
        .testTarget(
            name: "XcodeCleanerCLITests",
            dependencies: ["XcodeCleanerCLI", "XcodeInventoryCore"]
        ),
    ],
)
