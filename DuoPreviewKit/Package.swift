// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoPreviewKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DuoPreviewKit", targets: ["DuoPreviewKit"]),
    ],
    targets: [
        .target(
            name: "DuoPreviewKit",
            resources: [.process("Config/DuoPresets.json")]
        ),
        .testTarget(
            name: "DuoPreviewKitTests",
            dependencies: ["DuoPreviewKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
