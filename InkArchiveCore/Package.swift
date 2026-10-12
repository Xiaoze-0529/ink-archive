// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "InkArchiveCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "InkArchiveCore", targets: ["InkArchiveCore"])
    ],
    targets: [
        .target(name: "InkArchiveCore"),
        .testTarget(name: "InkArchiveCoreTests", dependencies: ["InkArchiveCore"])
    ]
)
