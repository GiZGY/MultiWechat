// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "wxmulti",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "wxmulti"
        ),
        .executableTarget(
            name: "wxmulti-menu"
        ),
        .testTarget(
            name: "wxmultiTests",
            dependencies: ["wxmulti", "wxmulti-menu"]
        ),
    ]
)
