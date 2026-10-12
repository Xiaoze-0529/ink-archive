// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "InkArchiveCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "InkArchiveCore", targets: ["InkArchiveCore"]),
        .executable(name: "InkArchiveValidate", targets: ["InkArchiveValidate"])
    ],
    targets: [
        .target(name: "InkArchiveCore"),
        .executableTarget(name: "InkArchiveValidate", dependencies: ["InkArchiveCore"]),
        .testTarget(name: "InkArchiveCoreTests", dependencies: ["InkArchiveCore"])
    ]
)
