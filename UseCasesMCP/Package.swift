// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "use-cases-mcp",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "use-cases-mcp", targets: ["use-cases-mcp"]),
  ],
  dependencies: [
    .package(path: "../UseCasesCore"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
  ],
  targets: [
    .executableTarget(
      name: "use-cases-mcp",
      dependencies: ["UseCasesMCP"],
    ),
    .target(
      name: "UseCasesMCP",
      dependencies: [
        .product(name: "UseCasesCore", package: "UseCasesCore"),
        .product(name: "MCP", package: "swift-sdk"),
      ],
    ),
    .testTarget(
      name: "UseCasesMCPTests",
      dependencies: [
        "UseCasesMCP",
        // The built binary: the corpus replay drives a real server over stdio.
        "use-cases-mcp",
        .product(name: "UseCasesCore", package: "UseCasesCore"),
        .product(name: "TestSupport", package: "UseCasesCore"),
      ],
    ),
  ],
)
