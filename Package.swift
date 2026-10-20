// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DS4Mate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DS4Mate", targets: ["DS4Mate"])
    ],
    targets: [
        .executableTarget(
            name: "DS4Mate",
            path: "Sources/DS4Mate",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
