// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clippet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clippet", targets: ["Clippet"])
    ],
    targets: [
        .executableTarget(
            name: "Clippet",
            path: "Sources/Clippet"
        )
    ]
)
