// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DesktopCanvasCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "DesktopCanvasCore", targets: ["DesktopCanvasCore"]),
    ],
    targets: [
        .target(
            name: "DesktopCanvasCore",
            path: "DesktopCanvas/Shared"
        ),
        .testTarget(
            name: "DesktopCanvasCoreTests",
            dependencies: ["DesktopCanvasCore"],
            path: "DesktopCanvasTests/CoreTests"
        ),
    ]
)
