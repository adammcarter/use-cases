import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct ShowCommandTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private static let wallet = [
    "# use-cases/pay.yml · READY",
    "id: shop.pay.wallet",
    "title: Wallet",
    "value_tier: core",
    "intent: wallet.",
    "scenarios:",
    "  - id: s",
    "    when: [x]",
    "    then: [y]",
    "validation:",
    "  - id: check",
    "    type: { kind: acceptance }",
    "    covers: [s]",
    "    procedure:",
    "      steps: [Check it.]",
  ]

  @Test
  func `show prints where the use case is and its state, then the YAML save would write`(
  ) async {
    let result = await workspace.run(["show", "shop.pay.wallet"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines == Self.wallet)
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `a draft is told apart on the first line`() async {
    let result = await workspace.run(["show", "shop.cart.share"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first == "# use-cases/cart.yml · DRAFT")
    #expect(result.outputLines.contains("id: shop.cart.share"))
  }

  @Test
  func `show --json is one document with the definition, its file, its state and its approval`(
  ) async throws {
    let result = await workspace.run(["--json", "show", "shop.pay.wallet"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(document["output_version"] == .integer(1))
    #expect(document["command"] == .string("show"))
    #expect(document["use_case"] == .string("shop.pay.wallet"))
    #expect(document["file"] == .string("use-cases/pay.yml"))
    #expect(document["state"] == .string("READY"))
    #expect(document["missing"] == .array([]))
    #expect(document["approval"] == .string("unapproved"))
    #expect(document["definition"]?["id"] == .string("shop.pay.wallet"))
    #expect(document["definition"]?["title"] == .string("Wallet"))
    #expect(document["definition"]?["value_tier"] == .string("core"))
    #expect(document["definition"]?["scenarios"] == .array([
      .object([
        "id": .string("s"),
        "when": .array([.string("x")]),
        "then": .array([.string("y")]),
      ]),
    ]))
  }

  @Test
  func `the flag works before the command or after it`() async {
    let before = await workspace.run(["--json", "show", "shop.pay.wallet"])
    let after = await workspace.run(["show", "shop.pay.wallet", "--json"])

    #expect(before == after)
  }

  @Test
  func `a draft says what it lacks`() async throws {
    let document = try await workspace.run(["--json", "show", "shop.cart.share"]).document()

    #expect(document["state"] == .string("DRAFT"))
    #expect(document["missing"] == .array([.string("value_tier")]))
    #expect(document["definition"]?["value_tier"] == nil)
  }

  @Test
  func `a use case that is not there is a usage error that says so`() async {
    let result = await workspace.run(["show", "shop.pay.nope"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error: no use case 'shop.pay.nope'"))
  }

  @Test(arguments: ["shop.pay", "shop", "wallet"])
  func `show takes a full id, never a prefix`(identifier: String) async {
    let result = await workspace.run(["show", identifier])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use case '\(identifier)'"))
    #expect(result.standardError.contains("full id"))
  }

  @Test
  func `a refusal is a document of the error schema, with show as its command`() async throws {
    let result = await workspace.run(["--json", "show", "shop.pay.nope"])
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["command"] == .string("show"))
    #expect(document["error"]?["kind"] == .string("usage"))
    guard case let .string(message)? = document["error"]?["message"] else {
      Issue.record("no message")
      return
    }

    #expect(message.contains("no use case"))
  }

  @Test
  func `show with no use case is a usage error`() async throws {
    let result = await workspace.run(["--json", "show"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
  }

  @Test
  func `a workspace that is INVALID is refused, not shown`() async throws {
    try workspace.folder.write("use-cases/broken.yml", "use_cases:\n  - id: [oops\n")

    let result = await workspace.run(["--json", "show", "shop.pay.wallet"])
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("invalid"))
    #expect(document["command"] == .string("show"))
  }

  @Test
  func `a promise that cannot be fingerprinted is a refusal, not a usage error`() async throws {
    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      shower: MockUseCaseShowing(refusing: .unfingerprintable(
        identifier: "shop.pay.wallet",
        reason: "x",
      )),
      workingDirectory: workspace.folder.url,
    ).run(arguments: ["--json", "show", "shop.pay.wallet"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
  }

  @Test
  func `show writes nothing`() async {
    _ = await workspace.run(["show", "shop.pay.wallet"])
    _ = await workspace.run(["--json", "show", "shop.cart.share"])

    #expect(!FileManager.default.fileExists(
      atPath: workspace.folder.url.appendingPathComponent(".use-cases").path,
    ))
  }
}
