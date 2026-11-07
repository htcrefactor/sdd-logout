// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LOGOUTCore",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS(.v14)],
    products: [.library(name: "LOGOUTCore", targets: ["LOGOUTCore"])],
    targets: [
        .target(name: "LOGOUTCore", path: "Sources/LOGOUTCore"),
        .testTarget(name: "LOGOUTCoreTests", dependencies: ["LOGOUTCore"], path: "Tests/LOGOUTCoreTests")
    ]
)
