import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct RemoveCommandTests {
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
  func `a use case is taken out of its file and nothing else changes`() async throws {
    let before = try read("use-cases/pay.yml").components(separatedBy: "\n")

    let result = await workspace.run(["remove", "shop.pay.wallet"])
    let after = try read("use-cases/pay.yml").components(separatedBy: "\n")

    #expect(result.exitCode == 0)
    #expect(result.outputLines == ["removed: shop.pay.wallet", "update  use-cases/pay.yml"])
    #expect(before.count - after.count == 14)
    #expect(!after.contains("  - id: wallet"))
    #expect(after.contains("  - id: card"))
  }

  @Test
  func `the last use case of a file takes the file with it`() async {
    _ = await workspace.run(["remove", "shop.cart.add", "--quiet"])
    let result = await workspace.run(["remove", "shop.cart.share"])

    #expect(result.outputLines == ["removed: shop.cart.share", "delete  use-cases/cart.yml"])
    #expect(!FileManager.default
      .fileExists(atPath: workspace.folder.url.appendingPathComponent("use-cases/cart.yml").path))
  }

  @Test
  func `a dry run says what would happen and writes nothing`() async throws {
    let before = try read("use-cases/pay.yml")

    let result = await workspace.run(["remove", "shop.pay.wallet", "--dry-run"])

    #expect(result.outputLines == [
      "would remove: shop.pay.wallet",
      "would update  use-cases/pay.yml",
    ])
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `its verdicts stay in the store`() async throws {
    await workspace.record("shop.pay.wallet", "pass")
    let runs = workspace.folder.url.appendingPathComponent(".use-cases/runs")
    let before = try FileManager.default.contentsOfDirectory(atPath: runs.path)

    _ = await workspace.run(["remove", "shop.pay.wallet"])

    #expect(try FileManager.default.contentsOfDirectory(atPath: runs.path) == before)
  }

  @Test
  func `the markers that still name the use case are warned about`() async throws {
    try workspace.folder.write(
      "tests/test_wallet.py",
      "# \(MarkerText.sentinel)shop.pay.wallet#check.s\ndef test_wallet():\n    pass\n"
        + "# \(MarkerText.sentinel)end shop.pay.wallet#check.s\n",
    )

    let result = await workspace.run(["remove", "shop.pay.wallet", "--json"])
    let document = try result.document()

    #expect(document["warnings"] == .array([
      .string("tests/test_wallet.py:2-3 is still marked for shop.pay.wallet"),
    ]))
    #expect(document["action"] == .string("removed"))
    #expect(document["use_case"] == .string("shop.pay.wallet"))
    #expect(document["file"] == .string("use-cases/pay.yml"))
    #expect(document["changes"] == .array([
      .object(["path": .string("use-cases/pay.yml"), "action": .string("replace")]),
    ]))
  }

  @Test(arguments: ["shop.pay.nope", "shop.pay", "wallet"])
  func `a use case that is not there is a usage error that says so`(identifier: String) async {
    let result = await workspace.run(["remove", identifier])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use case '\(identifier)'"))
  }

  @Test
  func `a group that names the use case by id keeps it from being removed`() async throws {
    try workspace.folder.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  money:\n    include: { ids: [shop.pay.wallet] }\n",
    )
    let before = try read("use-cases/pay.yml")

    let result = await workspace.run(["remove", "shop.pay.wallet"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use case"))
    #expect(try read("use-cases/pay.yml") == before)
  }

  @Test
  func `a workspace that is already invalid is refused`() async throws {
    try workspace.folder.write("use-cases/bad.yml", "use_cases:\n  - id: bad\n    surprise: true\n")

    let result = await workspace.run(["remove", "shop.pay.wallet"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("use-cases/bad.yml"))
  }
}
