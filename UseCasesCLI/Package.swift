// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "use-cases",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "use-cases", targets: ["use-cases"]),
  ],
  dependencies: [
    .package(path: "../UseCasesCore"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
  ],
  targets: [
    .executableTarget(
      name: "use-cases",
      dependencies: ["UseCasesCLI"],
    ),
    .target(
      name: "UseCasesCLI",
      dependencies: [
        .product(name: "UseCasesCore", package: "UseCasesCore"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
    ),
    .testTarget(
      name: "UseCasesCLITests",
      dependencies: [
        "UseCasesCLI",
        .product(name: "UseCasesCore", package: "UseCasesCore"),
        .product(name: "TestSupport", package: "UseCasesCore"),
      ],
    ),
  ],
)
