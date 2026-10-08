// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShiGuangCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ShiGuangCore", targets: ["ShiGuangCore"]),
    ],
    targets: [
        .target(name: "ShiGuangCore"),
        .testTarget(name: "ShiGuangCoreTests", dependencies: ["ShiGuangCore"]),
    ],
    swiftLanguageModes: [.v5]
)
