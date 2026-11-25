import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct SaveCommandTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func send(
    _ text: String,
    as name: String = "sent.yml",
  ) throws -> String {
    try workspace.folder.write(name, text)

    return name
  }

  private func read(_ path: String) throws -> String {
    try String(
      contentsOf: workspace.folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }

  private func save(
    _ text: String,
    _ flags: [String] = [],
  ) async throws -> CommandResult {
    let name = try send(text)

    return await workspace.run(["save", "--file", name] + flags)
  }

  @Test
  func `a use case of a new group is created in the file the structure gives it`() async throws {
    let result = try await save("id: shop.refunds.partial\ntitle: Refund part\n")

    #expect(result.exitCode == 0)
    #expect(result.outputLines == [
      "saved: shop.refunds.partial (created)",
      "create  use-cases/refunds.yml",
      "→ use-cases status shop.refunds.partial",
    ])
    #expect(
      try read("use-cases/refunds.yml")
        == "prefix: refunds\nuse_cases:\n  - id: partial\n    title: Refund part\n",
    )
  }

  @Test
  func `a use case of a group that has a file is added to it, the others untouched`() async throws {
    let before = try read("use-cases/pay.yml")

    let result = try await save("id: shop.pay.crypto\ntitle: Pay with crypto\n")
    let after = try read("use-cases/pay.yml")

    #expect(result.outputLines.first == "saved: shop.pay.crypto (added)")
    #expect(after.hasPrefix(before))
    #expect(after.hasSuffix("  - id: crypto\n    title: Pay with crypto\n"))
  }

  @Test
  func `a use case that is there is replaced and the lines around it stay`() async throws {
    let before = try read("use-cases/pay.yml").components(separatedBy: "\n")

    let result = try await save(
      "id: shop.pay.wallet\ntitle: Wallet, retitled\nvalue_tier: core\nintent: wallet.\n"
        + "scenarios:\n  - id: s\n    when: [x]\n    then: [y]\nvalidation:\n  - id: check\n"
        +
        "    type: { kind: acceptance }\n    covers: [s]\n    procedure:\n"
        + "      steps: [Check it.]\n",
    )
    let after = try read("use-cases/pay.yml").components(separatedBy: "\n")

    #expect(result.outputLines.first == "saved: shop.pay.wallet (replaced)")
    #expect(before.count == after.count)
    #expect(zip(before, after).filter { $0 != $1 }.map(\.1) == ["    title: Wallet, retitled"])
  }

  @Test
  func `a use case sent as it is changes nothing and says so`() async throws {
    let shown = await workspace.run(["show", "shop.pay.wallet"]).outputLines.dropFirst()
    let before = try read("use-cases/pay.yml")

    let result = try await save(shown.joined(separator: "\n") + "\n")

    #expect(result.outputLines.first == "saved: shop.pay.wallet (unchanged)")
    #expect(result.outputLines.count == 2)
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a dry run says what would happen and writes nothing`() async throws {
    let before = try read("use-cases/pay.yml")

    let result = try await save("id: shop.refunds.partial\ntitle: T\n", ["--dry-run"])

    #expect(result.outputLines == [
      "would save: shop.refunds.partial (created)",
      "would create  use-cases/refunds.yml",
    ])
    #expect(try read("use-cases/pay.yml") == before)
    #expect(!FileManager.default
      .fileExists(atPath: workspace.folder.url.appendingPathComponent("use-cases/refunds.yml")
        .path))
  }

  @Test
  func `the document of a save names the use case, the file, the action and the changes`(
  ) async throws {
    let document = try await save("id: shop.refunds.partial\ntitle: T\n", ["--json"]).document()

    #expect(document["command"] == .string("save"))
    #expect(document["use_case"] == .string("shop.refunds.partial"))
    #expect(document["file"] == .string("use-cases/refunds.yml"))
    #expect(document["action"] == .string("created"))
    #expect(document["changes"] == .array([
      .object(["path": .string("use-cases/refunds.yml"), "action": .string("create")]),
    ]))
    #expect(document["warnings"] == .array([]))
    #expect(document["dry_run"] == .boolean(false))
  }

  @Test
  func `quiet leaves out the hint`() async throws {
    let result = try await save("id: shop.refunds.partial\ntitle: T\n", ["--quiet"])

    #expect(result.outputLines.last == "create  use-cases/refunds.yml")
  }

  @Test(arguments: [
    ("id: orphan\ntitle: T\n", "has no group"),
    ("id: shop.loose\ntitle: T\n", "need a group"),
    ("title: no id\n", "full id"),
    ("- id: shop.a.b\n- id: shop.a.c\n", "one mapping with its full id"),
    ("id: shop.pay.x\ntitle: T\nrunner: swift\n", "runner"),
  ])
  func `a use case that cannot be saved is a refusal that says why, and nothing is written`(
    text: String,
    words: String,
  ) async throws {
    let before = try read("use-cases/pay.yml")

    let result = try await save(text)

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains(words))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a use case that breaks the workspace's rules is invalid, a bad input is usage`(
  ) async throws {
    let invalid = try await save("id: shop.pay.x\ntitle: T\nrunner: swift\n", ["--json"]).document()
    let usage = try await save("title: no id\n", ["--json"]).document()

    #expect(invalid["error"]?["kind"] == .string("invalid"))
    #expect(usage["error"]?["kind"] == .string("usage"))
    #expect(invalid["command"] == .string("save"))
  }

  @Test
  func `a file that is not there is a refusal that says so`() async {
    let result = await workspace.run(["save", "--file", "missing.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("is not a file"))
  }

  @Test
  func `a save asks for a file`() async {
    let result = await workspace.run(["save"])

    #expect(result.exitCode == 2)
  }

  @Test
  func `an id a group names cannot be taken away by saving it elsewhere, the workspace stays valid`(
  ) async throws {
    try workspace.folder.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  money:\n    include: { prefixes: [shop.pay] }\n",
    )

    let result = try await save("id: shop.pay.crypto\ntitle: T\n")

    #expect(result.exitCode == 0)
  }
}
