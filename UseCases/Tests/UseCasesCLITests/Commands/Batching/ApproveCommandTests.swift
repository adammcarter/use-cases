import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct ApproveCommandTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func read(_ path: String) throws -> String {
    try String(
      contentsOf: workspace.folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }

  @Test
  func `a sign-off is recorded on the use case with the name, today and a fingerprint`(
  ) async throws {
    let result = await workspace.run(["approve", "shop.pay.card", "--by", "Kim"])
    let text = try read("use-cases/pay.yml")

    #expect(result.exitCode == 0)
    #expect(result.outputLines == [
      "approved  shop.pay.card",
      "",
      "update  use-cases/pay.yml",
    ])
    #expect(text.contains("approved:\n"))
    #expect(text.contains("by: Kim\n"))
    #expect(text.range(of: #""on": "\d{4}-\d{2}-\d{2}"\n"#, options: .regularExpression) != nil)
    #expect(text.contains("behaviour: "))
  }

  @Test
  func `the use case reads as approved afterwards, and the others do not`() async throws {
    _ = await workspace.run(["approve", "shop.pay.card", "--by", "Kim"])

    let card = try await workspace.run(["--json", "show", "shop.pay.card"]).document()
    let wallet = try await workspace.run(["--json", "show", "shop.pay.wallet"]).document()

    #expect(card["approval"] == .string("approved"))
    #expect(wallet["approval"] == .string("unapproved"))
  }

  @Test
  func `a use case approved as it reads is unchanged, whoever asks again`() async throws {
    _ = await workspace.run(["approve", "shop.pay.card", "--by", "Kim"])
    let before = try read("use-cases/pay.yml")

    let result = await workspace.run(["approve", "shop.pay.card", "--by", "Sam"])

    #expect(result.outputLines == ["unchanged  shop.pay.card"])
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a dry run says what would happen and writes nothing`() async throws {
    let before = try read("use-cases/pay.yml")

    let result = await workspace.run(["approve", "shop.pay.card", "--by", "Kim", "--dry-run"])

    #expect(result.outputLines == [
      "would approve  shop.pay.card",
      "",
      "would update  use-cases/pay.yml",
    ])
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test(arguments: [[], ["--dry-run"]])
  func `with no use case to approve it says nothing needs approval, never nothing at all`(
    dryRun: [String],
  ) async throws {
    for file in ["use-cases/pay.yml", "use-cases/cart.yml"] {
      try FileManager.default.removeItem(at: workspace.folder.url.appendingPathComponent(file))
    }

    let result = await workspace.run(["approve", "--all", "--by", "Sam"] + dryRun)

    #expect(result.exitCode == 0)
    #expect(result.outputLines == ["nothing needs approval"])
  }

  @Test
  func `all approves every use case, drafts included, in id order`() async throws {
    let result = try await workspace.run(["approve", "--all", "--by", "Kim", "--json"]).document()

    #expect(result["use_cases"]?.useCases == [
      "shop.cart.add", "shop.cart.share", "shop.pay.card", "shop.pay.gift", "shop.pay.refund",
      "shop.pay.voucher", "shop.pay.wallet",
    ])
    #expect(result["changes"] == .array([
      .object(["path": .string("use-cases/cart.yml"), "action": .string("replace")]),
      .object(["path": .string("use-cases/pay.yml"), "action": .string("replace")]),
    ]))
    #expect(result["by"] == .string("Kim"))
  }

  @Test
  func `every use case of a file keeps its sign-off when several are approved together`(
  ) async throws {
    _ = await workspace.run(["approve", "--all", "--by", "Kim"])

    for useCase in ["card", "wallet", "refund", "voucher", "gift"] {
      let shown = try await workspace.run(["--json", "show", "shop.pay.\(useCase)"]).document()

      #expect(shown["approval"] == .string("approved"))
    }
  }

  @Test
  func `a name is trimmed`() async throws {
    let document = try await workspace.run(["approve", "shop.pay.card", "--by", " Kim ", "--json"])
      .document()

    #expect(document["by"] == .string("Kim"))
  }

  // MARK: - Refused

  @Test(arguments: [
    (["shop.pay.card", "--all"], "not both"),
    ([], "not both"),
    (["shop.pay.nope"], "no use case"),
  ])
  func `a request that cannot be taken is a refusal that says why, and nothing is written`(
    arguments: [String],
    words: String,
  ) async throws {
    let before = try read("use-cases/pay.yml")

    let result = await workspace.run(["approve"] + arguments + ["--by", "Kim"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains(words))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `every refusal of approve is a usage error`() async throws {
    let blank = try await workspace.run(["approve", "--all", "--by", " ", "--json"]).document()
    let both = try await workspace.run(["approve", "shop.pay.card", "--all", "--by", "A", "--json"])
      .document()
    let unknown = try await workspace.run(["approve", "shop.pay.nope", "--by", "A", "--json"])
      .document()

    for document in [blank, both, unknown] {
      #expect(document["error"]?["kind"] == .string("usage"))
      #expect(document["command"] == .string("approve"))
    }
  }

  @Test(arguments: ["", " ", "\t"])
  func `a blank name is refused`(name: String) async throws {
    let before = try read("use-cases/pay.yml")

    let result = await workspace.run(["approve", "--all", "--by", name])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("names who signed off"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a name longer than two hundred characters is refused`() async {
    let result = await workspace.run([
      "approve", "shop.pay.card", "--by", String(repeating: "a", count: 201),
    ])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("names who signed off"))
  }

  @Test
  func `approve asks who signed off`() async {
    let result = await workspace.run(["approve", "shop.pay.card"])

    #expect(result.exitCode == 2)
  }

  // MARK: - Only the approved field changes

  /// A file whose use case has a sign-off with a comment inside it, which approving again
  /// has to write over.
  private func writeSignedWithComment() throws {
    try workspace.folder.write(
      "use-cases/noted.yml",
      "# kept\nprefix: noted\nuse_cases:\n  - id: item\n    # about the title\n"
        + "    title: Item\n    bindings: []\n    approved:\n      # who\n      by: Sam\n"
        +
        "      \"on\": \"2026-01-01\"\n      behaviour: \"\(String(repeating: "0", count: 64))\"\n",
    )
  }

  @Test
  func `comments and empty lists outside the approved field are kept`() async throws {
    try workspace.folder.write(
      "use-cases/noted.yml",
      "# kept\nprefix: noted\nuse_cases:\n  - id: item\n    # about the title\n"
        + "    title: Item\n    bindings: []\n",
    )

    let result = await workspace.run(["approve", "shop.noted.item", "--by", "Kim"])
    let text = try read("use-cases/noted.yml")

    #expect(result.exitCode == 0)
    #expect(!result.outputLines.contains { line in line.hasPrefix("warning:") })
    #expect(text
      .hasPrefix("# kept\nprefix: noted\nuse_cases:\n  - id: item\n    # about the title\n"))
    #expect(text.contains("    title: Item\n    bindings: []\n    approved:\n"))
  }

  @Test
  func `a comment inside a sign-off that is written again is dropped, and said`() async throws {
    try writeSignedWithComment()

    let result = await workspace.run(["approve", "shop.noted.item", "--by", "Kim"])

    #expect(result.outputLines.last?.hasPrefix("warning: ") == true)
    #expect(result.outputLines.last?.contains("# who") == true)
    #expect(try read("use-cases/noted.yml").contains("# about the title"))
    #expect(try !read("use-cases/noted.yml").contains("# who"))
  }

  // MARK: - What a script is told

  @Test
  func `the warnings are in the document only, as with save and apply`() async throws {
    try writeSignedWithComment()

    let json = await workspace.run(["approve", "shop.noted.item", "--by", "Kim", "--json"])
    let warnings = try #require(json.document()["warnings"]?.strings)

    #expect(warnings.count == 1)
    #expect(warnings.first?.contains("# who") == true)
    #expect(json.standardError.isEmpty)
  }

  @Test
  func `a document with no warnings has an empty list of them and nothing on the standard error`(
  ) async throws {
    let json = await workspace.run(["approve", "shop.pay.card", "--by", "Kim", "--json"])

    #expect(try json.document()["warnings"] == .array([]))
    #expect(json.standardError.isEmpty)
  }

  @Test
  func `the document ends with one line break, as the document of save does`() async {
    let json = await workspace.run(["approve", "shop.pay.card", "--by", "Kim", "--json"])

    #expect(json.standardOutput.hasSuffix("}\n"))
    #expect(!json.standardOutput.hasSuffix("\n\n"))
  }
}

private extension JSONValue {
  /// The `use_case` of each entry of an array of objects.
  var useCases: [String] {
    guard case let .array(items) = self else {
      return []
    }

    return items.compactMap { item in
      guard case let .string(text)? = item["use_case"] else {
        return nil
      }

      return text
    }
  }
}
