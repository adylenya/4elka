// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Chelka",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Chelka", targets: ["Chelka"]),
        .library(name: "ChelkaCore", targets: ["ChelkaCore"]),
    ],
    targets: [
        .executableTarget(name: "Chelka", dependencies: ["ChelkaCore"]),
        .target(name: "ChelkaCore"),
        .testTarget(
            name: "ChelkaCoreTests",
            dependencies: ["ChelkaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
