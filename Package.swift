// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HyMT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyMT", targets: ["HyMT"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "HyMT",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/HyMT"
        ),
        .testTarget(
            name: "HyMTTests",
            dependencies: ["HyMT"],
            path: "Tests/HyMTTests"
        )
    ]
)
