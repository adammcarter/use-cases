// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]

let package = Package(
  name: "UseCases",
  platforms: [.macOS(.v14)],
  products: [
    .executable(
      name: "use-cases",
      targets: ["use-cases"],
    ),
    .executable(
      name: "use-cases-transformers",
      targets: ["use-cases-transformers"],
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      from: "1.8.2",
    ),
    .package(
      url: "https://github.com/jpsim/Yams.git",
      exact: "6.2.2",
    ),
    .package(
      url: "https://github.com/apple/swift-crypto.git",
      exact: "5.0.1",
    ),
    .package(
      url: "https://github.com/modelcontextprotocol/swift-sdk.git",
      exact: "0.12.1",
    ),
    .package(
      url: "https://github.com/apple/swift-atomics.git",
      exact: "1.3.1",
    ),
  ],
  targets: [
    .target(
      name: "UseCasesCore",
      dependencies: [
        .product(
          name: "Yams",
          package: "Yams",
        ),
        .product(
          name: "Crypto",
          package: "swift-crypto",
        ),
      ],
      resources: [
        .copy("Resources/Schemas"),
        .copy("Resources/Guides"),
      ],
      swiftSettings: strict,
    ),
    .target(
      name: "UseCasesCLI",
      dependencies: [
        "UseCasesCore",
        .product(
          name: "ArgumentParser",
          package: "swift-argument-parser",
        ),
      ],
      swiftSettings: strict,
    ),
    .target(
      name: "UseCasesMCP",
      dependencies: [
        "UseCasesCore",
        .product(
          name: "MCP",
          package: "swift-sdk",
        ),
      ],
      resources: [
        .copy("Resources/Schemas"),
      ],
      swiftSettings: strict,
    ),
    .executableTarget(
      name: "use-cases",
      dependencies: [
        "UseCasesCLI",
        "UseCasesCore",
        "UseCasesMCP",
      ],
      swiftSettings: strict,
    ),
    .target(
      name: "UseCasesTransformers",
      swiftSettings: strict,
    ),
    .executableTarget(
      name: "use-cases-transformers",
      dependencies: ["UseCasesTransformers"],
      swiftSettings: strict,
    ),
    .target(
      name: "UseCasesTestSupport",
      dependencies: [
        "UseCasesCore",
        .product(
          name: "Atomics",
          package: "swift-atomics",
        ),
      ],
      path: "Tests/UseCasesTestSupport",
      swiftSettings: strict,
    ),
    .testTarget(
      name: "UseCasesCoreTests",
      dependencies: [
        "UseCasesCore",
        "UseCasesTestSupport",
      ],
      swiftSettings: strict,
    ),
    .testTarget(
      name: "UseCasesCLITests",
      dependencies: [
        "UseCasesCLI",
        "UseCasesMCP",
        "UseCasesTestSupport",
      ],
      swiftSettings: strict,
    ),
    .testTarget(
      name: "UseCasesMCPTests",
      dependencies: [
        "UseCasesMCP",
        "UseCasesTestSupport",
        .product(
          name: "MCP",
          package: "swift-sdk",
        ),
      ],
      swiftSettings: strict,
    ),
    .testTarget(
      name: "use-casesTests",
      dependencies: [
        "use-cases",
        "UseCasesCLI",
        "UseCasesCore",
        "UseCasesMCP",
        "UseCasesTestSupport",
        .product(
          name: "MCP",
          package: "swift-sdk",
        ),
      ],
      swiftSettings: strict,
    ),
    .testTarget(
      name: "UseCasesTransformersTests",
      dependencies: ["UseCasesTransformers"],
      swiftSettings: strict,
    ),
    .testTarget(
      name: "use-cases-transformersTests",
      dependencies: ["use-cases-transformers"],
      swiftSettings: strict,
    ),
  ],
)
