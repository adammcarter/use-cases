// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RateLimit",
    products: [.library(name: "RateLimit", targets: ["RateLimit"])],
    targets: [
        .target(name: "RateLimit"),
        .testTarget(name: "RateLimitTests", dependencies: ["RateLimit"]),
    ]
)
