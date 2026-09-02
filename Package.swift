// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuzikOdam",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MuzikOdam", targets: ["MuzikOdam"])
    ],
    targets: [
        .executableTarget(name: "MuzikOdam")
    ],
    swiftLanguageModes: [.v5]
)
