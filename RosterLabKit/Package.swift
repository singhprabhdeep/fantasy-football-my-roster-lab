// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RosterLabKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RosterLabKit", targets: ["RosterLabKit"]),
    ],
    targets: [
        .target(name: "RosterLabKit"),
        .testTarget(name: "RosterLabKitTests", dependencies: ["RosterLabKit"]),
    ]
)
