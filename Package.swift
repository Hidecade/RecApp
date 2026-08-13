// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RecApp", targets: ["RecApp"])
    ],
    targets: [
        .executableTarget(
            name: "RecApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
