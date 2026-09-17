// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "UseCasesCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "UseCasesCore", targets: ["UseCasesCore"]),
    .library(name: "TestSupport", targets: ["TestSupport"]),
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.5.0"),
  ],
  targets: [
    .target(
      name: "UseCasesCore",
      dependencies: [
        .product(name: "Yams", package: "Yams"),
        .product(name: "Crypto", package: "swift-crypto"),
      ],
    ),
    .target(
      name: "TestSupport",
      dependencies: ["UseCasesCore"],
    ),
    .testTarget(
      name: "UseCasesCoreTests",
      dependencies: ["UseCasesCore", "TestSupport"],
    ),
  ],
)
