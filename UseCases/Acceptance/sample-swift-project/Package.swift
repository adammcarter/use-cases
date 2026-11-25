// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Auth",
    targets: [
        .target(name: "Auth"),
        .testTarget(name: "AuthTests", dependencies: ["Auth"]),
        .testTarget(name: "SessionTests", dependencies: ["Auth"]),
    ]
)
