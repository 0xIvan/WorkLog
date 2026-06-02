// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Worklog",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Worklog", targets: ["Worklog"])
    ],
    targets: [
        .target(
            name: "WorklogCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Worklog",
            dependencies: ["WorklogCore"]
        ),
        .testTarget(
            name: "WorklogCoreTests",
            dependencies: ["WorklogCore"]
        )
    ]
)
