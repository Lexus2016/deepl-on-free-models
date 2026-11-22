// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HyMT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyMT", targets: ["HyMT"])
    ],
    targets: [
        .executableTarget(
            name: "HyMT",
            path: "Sources/HyMT"
        )
    ]
)
