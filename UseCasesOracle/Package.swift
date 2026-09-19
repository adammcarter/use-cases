// swift-tools-version: 6.2
import PackageDescription

// The black-box oracle (ADR 0007 decision 2), in Swift.
//
// It depends on NOTHING. That is the point: an oracle that links UseCasesCore
// could shortcut an assertion through the very code it is meant to hold to
// account, and one that depends on the CLI or MCP package would stop compiling
// the day row 10d deletes something. The binaries under test arrive as
// processes, named by UC_BIN / UC_MCP_BIN exactly as the TypeScript oracle's
// `tests/helpers/{uc-binary,mcp-server}.ts` name them, so the same suite can be
// pointed at the Swift build or at the committed Node bundle.
//
// The cost of zero dependencies is that `swift test` here does not build the
// binaries. So a missing or unrunnable binary fails loudly and is never
// silently replaced by a fallback — `HarnessTests` pins that.
let package = Package(
  name: "UseCasesOracle",
  platforms: [.macOS(.v14)],
  targets: [
    .testTarget(
      name: "OracleTests",
    ),
  ],
)
