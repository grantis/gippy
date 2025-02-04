// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "GippyCLI",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.6.4")
    ],
    targets: [
        .executableTarget(
            name: "GippyCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Alamofire"
            ]
        )
    ]
)
