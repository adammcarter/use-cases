import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct ApplyCommandTests {
  private static let batch = """
  remove: [shop.pay.gift]
  save:
    - id: shop.pay.wallet
      title: Wallet, retitled
    - id: shop.refunds.partial
      title: Refund part
  """

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

  private func apply(
    _ text: String,
    _ flags: [String] = [],
  ) async throws -> CommandResult {
    try workspace.folder.write("batch.yml", text)

    return await workspace.run(["apply", "--file", "batch.yml"] + flags)
  }

  private func isThere(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: workspace.folder.url.appendingPathComponent(path).path)
  }

  @Test
  func `people see the batch in the order it runs, then the files it changes`() async throws {
    let result = try await apply(Self.batch, ["--dry-run"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines == [
      "would delete  shop.pay.gift",
      "would add     shop.refunds.partial",
      "would update  shop.pay.wallet",
      "",
      "would update  use-cases/pay.yml",
      "would create  use-cases/refunds.yml",
    ])
  }

  @Test
  func `the batch is applied as the dry run said, in one write`() async throws {
    let dry = try await apply(Self.batch, ["--dry-run", "--json"]).document()
    let result = try await apply(Self.batch)
    let real = try await workspace.run(["--json", "apply", "--file", "batch.yml"]).document()

    #expect(result.exitCode == 0)
    #expect(result.outputLines == [
      "delete  shop.pay.gift",
      "add     shop.refunds.partial",
      "update  shop.pay.wallet",
      "",
      "update  use-cases/pay.yml",
      "create  use-cases/refunds.yml",
    ])
    #expect(dry["dry_run"] == .boolean(true))
    #expect(dry["use_cases"] != nil)
    #expect(real["error"] != nil) // the gift is gone now: the same batch no longer applies
    #expect(
      try read("use-cases/refunds.yml")
        == "prefix: refunds\nuse_cases:\n  - id: partial\n    title: Refund part\n",
    )
    #expect(try !read("use-cases/pay.yml").contains("id: gift"))
    #expect(try read("use-cases/pay.yml").contains("title: Wallet, retitled"))
  }

  @Test
  func `a dry run writes nothing`() async throws {
    let before = try read("use-cases/pay.yml")

    _ = try await apply(Self.batch, ["--dry-run"])

    #expect(try read("use-cases/pay.yml") == before)
    #expect(!isThere("use-cases/refunds.yml"))
  }

  @Test
  func `the document lists each use case in the order it ran, and the files by path`(
  ) async throws {
    let document = try await apply(Self.batch, ["--json"]).document()

    #expect(document["command"] == .string("apply"))
    #expect(document["use_cases"] == .array([
      .object([
        "use_case": .string("shop.pay.gift"),
        "file": .string("use-cases/pay.yml"),
        "action": .string("removed"),
      ]),
      .object([
        "use_case": .string("shop.refunds.partial"),
        "file": .string("use-cases/refunds.yml"),
        "action": .string("created"),
      ]),
      .object([
        "use_case": .string("shop.pay.wallet"),
        "file": .string("use-cases/pay.yml"),
        "action": .string("replaced"),
      ]),
    ]))
    #expect(document["changes"] == .array([
      .object(["path": .string("use-cases/pay.yml"), "action": .string("replace")]),
      .object(["path": .string("use-cases/refunds.yml"), "action": .string("create")]),
    ]))
    #expect(document["warnings"] == .array([]))
    #expect(document["dry_run"] == .boolean(false))
  }

  @Test
  func `the keys of a proposal file beside the batch are accepted and ignored`() async throws {
    let result = try await apply(
      Self.batch + "\ntitle: Refunds\nuntouched: [shop.pay.card]\nfits: {}\nyou_see: {}\n"
        + "decisions: []\ngolden: {}\n",
      ["--dry-run"],
    )

    #expect(result.exitCode == 0)
    #expect(result.outputLines.count == 6)
  }

  @Test
  func `a batch whose use cases are all as they are writes nothing and says so`() async throws {
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    let yaml = shown.enumerated().map { number, line in
      number == 0 ? "  - \(line)" : "    \(line)"
    }.joined(separator: "\n")
    let before = try read("use-cases/pay.yml")

    let result = try await apply("save:\n\(yaml)\n")

    #expect(result.outputLines == ["keep    shop.pay.wallet"])
    #expect(try read("use-cases/pay.yml") == before)
  }

  // MARK: - All or nothing

  @Test(arguments: [
    "{}\n",
    "remove: []\nsave: []\n",
    "rename: [x]\n",
    "remove: shop.pay.card\n",
    "remove: [shop.pay.card]\nsave:\n  - id: shop.pay.card\n    title: T\n",
    "remove: [shop.pay.nope]\n",
    "save:\n  - id: shop.pay.fine\n    title: Fine\n  - id: orphan\n    title: No group\n",
  ])
  func `a bad batch is a refusal and writes nothing at all`(text: String) async throws {
    let before = try read("use-cases/pay.yml")

    let result = try await apply(text)

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error: "))
    #expect(try read("use-cases/pay.yml") == before)
    #expect(try read("use-cases/cart.yml").contains("share"))
  }

  @Test
  func `a change that would leave the workspace invalid refuses the whole batch`() async throws {
    let before = try read("use-cases/pay.yml")
    let result = try await apply(
      """
      save:
        - id: shop.pay.fine
          title: Fine on its own
        - id: shop.pay.broken
          title: Broken
          scenarios:
            - id: s
              when: [x]
              then: [y]
          validation:
            - id: r
              type: { kind: unit }
              covers: [nope]
      """,
      ["--json"],
    )
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("invalid"))
    #expect(document["command"] == .string("apply"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a bad request is usage, whatever is wrong with the batch`() async throws {
    for text in ["{}\n", "remove: [shop.pay.nope]\n"] {
      let document = try await apply(text, ["--json"]).document()

      #expect(document["error"]?["kind"] == .string("usage"))
    }
  }

  @Test
  func `apply asks for a file`() async {
    let result = await workspace.run(["apply"])

    #expect(result.exitCode == 2)
  }

  @Test
  func `a file that is not there is a refusal that says so`() async {
    let result = await workspace.run(["apply", "--file", "missing.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("is not a file"))
  }

  @Test
  func `the document ends with one line break, as the document of save does`() async throws {
    let result = try await apply(Self.batch, ["--json"])

    #expect(result.standardOutput.hasSuffix("}\n"))
    #expect(!result.standardOutput.hasSuffix("\n\n"))
  }

  @Test
  func `a blank remove or a blank save is an empty list`() async throws {
    let removing = try await apply("remove:\nsave:\n  - id: shop.pay.crypto\n    title: T\n", [
      "--dry-run",
    ])
    let saving = try await apply("remove: [shop.pay.gift]\nsave:\n", ["--dry-run"])
    let neither = try await apply("remove:\nsave:\n")

    #expect(removing.outputLines.first == "would add     shop.pay.crypto")
    #expect(saving.outputLines.first == "would delete  shop.pay.gift")
    #expect(neither.exitCode == 2)
    #expect(neither.standardError.contains("a batch is a mapping"))
  }

  // MARK: - A signed-off batch

  @Test
  func `a signed-off batch approves each use case it saves, in the same write`() async throws {
    let result = try await apply(Self.batch, ["--approved-by", "Kim"])

    #expect(result.exitCode == 0)

    for identifier in ["shop.pay.wallet", "shop.refunds.partial"] {
      let shown = try await workspace.run(["--json", "show", identifier]).document()

      #expect(shown["approval"] == .string("approved"))
    }

    let untouched = try await workspace.run(["--json", "show", "shop.pay.card"]).document()

    #expect(untouched["approval"] == .string("unapproved"))
  }

  @Test
  func `a save otherwise unchanged is replaced when the batch is signed off`() async throws {
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    let yaml = shown.enumerated().map { number, line in
      number == 0 ? "  - \(line)" : "    \(line)"
    }.joined(separator: "\n")

    let result = try await apply("save:\n\(yaml)\n", ["--approved-by", "Kim", "--json"])
    let document = try result.document()

    #expect(document["use_cases"]?.actions == ["replaced"])
    #expect(try read("use-cases/pay.yml").contains("approved:"))
  }

  @Test
  func `a save that brings a sign-off of its own is refused even when the batch is signed off`(
  ) async throws {
    let result = try await apply(
      """
      save:
        - id: shop.pay.wallet
          title: T
          approved:
            by: Someone
            "on": "2026-01-01"
            behaviour: "\(String(repeating: "a", count: 64))"
      """,
      ["--approved-by", "Kim"],
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("never by save"))
  }

  @Test
  func `a use case someone else approved as it reads is kept as they approved it`() async throws {
    _ = await workspace.run(["approve", "shop.pay.wallet", "--by", "Sam"])
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    let yaml = shown.enumerated().map { number, line in
      number == 0 ? "  - \(line)" : "    \(line)"
    }.joined(separator: "\n")
    let before = try read("use-cases/pay.yml")

    let result = try await apply("save:\n\(yaml)\n", ["--approved-by", "Zed"])

    #expect(result.outputLines == ["keep    shop.pay.wallet"])
    #expect(try read("use-cases/pay.yml") == before)
    #expect(try !read("use-cases/pay.yml").contains("by: Zed"))
  }

  @Test
  func `the name of the signature is trimmed before its length is looked at`() async throws {
    let name = String(repeating: "a", count: 200)

    let result = try await apply(Self.batch, ["--approved-by", "  \(name)  ", "--json"])

    #expect(result.exitCode == 0)
    #expect(try read("use-cases/pay.yml").contains("by: \(name)\n"))
  }

  @Test(arguments: ["", " ", "\t"])
  func `a blank name for the signature is refused`(name: String) async throws {
    let result = try await apply(
      Self.batch,
      ["--approved-by", name],
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("names who signed off"))
    #expect(!isThere("use-cases/refunds.yml"))
  }

  @Test
  func `a name of more than two hundred characters for the signature is refused`() async throws {
    let result = try await apply(
      Self.batch,
      ["--approved-by", String(repeating: "a", count: 201)],
    )

    #expect(result.exitCode == 2)
    #expect(!isThere("use-cases/refunds.yml"))
  }
}

private extension JSONValue {
  /// The `action` of each entry of an array of objects.
  var actions: [String] {
    guard case let .array(items) = self else {
      return []
    }

    return items.compactMap { item in
      item["action"]?.text
    }
  }

  var text: String? {
    guard case let .string(text) = self else {
      return nil
    }

    return text
  }
}
