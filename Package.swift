// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "dnotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "dnotes", targets: ["Dnotes"]),
        .library(name: "DnotesCore", targets: ["DnotesCore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "DnotesCore"),
        .executableTarget(name: "Dnotes", dependencies: ["DnotesCore"]),
        .testTarget(name: "DnotesCoreTests", dependencies: ["DnotesCore"]),
    ]
)
