// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShiGuangCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ShiGuangCore", targets: ["ShiGuangCore"]),
    ],
    targets: [
        .target(name: "ShiGuangCore"),
        .testTarget(name: "ShiGuangCoreTests", dependencies: ["ShiGuangCore"]),
    ]
)
