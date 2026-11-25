import Foundation
import Testing
@testable import UseCasesCLI

struct StatusCommandGroupTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
    try workspace.folder.write(
      "use-case-groups.yml",
      """
      schema_version: 1
      groups:
        release:
          description: What ships.
          include: { prefixes: [shop.pay] }
        cart:
          include: { prefixes: [shop.cart] }
        nothing-yet:
          include: { prefixes: [shop.cart] }
          exclude: { prefixes: [shop.cart] }\n
      """,
    )
  }

  private func members(_ arguments: [String]) async throws -> [String] {
    let result = await workspace.run(["--json", "status"] + arguments)
    let document = try result.document()

    guard case let .array(useCases)? = document["use_cases"] else {
      Issue.record("no use_cases in \(result.standardOutput) \(result.standardError)")
      return []
    }

    return useCases.compactMap { useCase in
      guard case let .string(identifier)? = useCase["use_case"] else {
        return nil
      }

      return identifier
    }
  }

  @Test
  func `a group lists its members only, drafts included`() async throws {
    #expect(try await members(["--group", "release"]).count == 5)
    #expect(try await members(["--group", "cart"]) == ["shop.cart.add", "shop.cart.share"])
  }

  @Test
  func `the json document says which group it is about, and only with a group`() async throws {
    let grouped = try await workspace.run(["--json", "status", "--group", "cart"]).document()
    let plain = try await workspace.run(["--json", "status"]).document()
    let failures = try PublishedSchema(path: "schemas/output/cli-status.schema.json")
      .failures(of: grouped)

    #expect(grouped["group"] == .string("cart"))
    #expect(grouped["summary"]?["total"] == .integer(2))
    #expect(plain["group"] == nil)
    #expect(failures == [])
  }

  @Test
  func `the group, the target and the states all have to hold`() async throws {
    try await workspace.recordEveryState()

    #expect(try await members(["--group", "release", "shop.pay.card"]) == ["shop.pay.card"])
    #expect(try await members(["--group", "release", "shop.cart"]).isEmpty)
    #expect(try await members(["--group", "release", "--state", "failed,stale"]) == [
      "shop.pay.card",
      "shop.pay.refund",
    ])
    #expect(try await members(["--group", "cart", "--state", "draft"]) == ["shop.cart.share"])
  }

  @Test
  func `a group that has no members lists nothing and is no error`() async throws {
    let result = await workspace.run(["status", "--group", "nothing-yet"])

    #expect(result.exitCode == 0)
    #expect(try await members(["--group", "nothing-yet"]).isEmpty)
  }

  @Test
  func `a group is a filtered view, so a checkout where nothing has run lists it as usual`(
  ) async {
    let result = await workspace.run(["status", "--group", "release"])

    #expect(result.exitCode == 0)
    #expect(!result.standardOutput.contains("no verdicts in this checkout yet"))
    #expect(result.outputLines.first?.contains("shop.pay.") == true)
  }

  @Test
  func `the gate of a group holds its members and no other use case`() async throws {
    await workspace.record("shop.cart.add", "fail")

    let release = await workspace.run(["--json", "status", "--gate", "--group", "release"])
    let cart = await workspace.run(["--json", "status", "--gate", "--group", "cart"])
    let everything = await workspace.run(["--json", "status", "--gate"])

    #expect(release.exitCode == 0)
    #expect(cart.exitCode == 1)
    #expect(everything.exitCode == 1)
    #expect(try release.document()["gate"]?["passed"] == .boolean(true))
    #expect(try release.document()["summary"]?["total"] == .integer(5))
    #expect(try cart.document()["gate"]?["blocking"] == .array([
      .object(["use_case": .string("shop.cart.add"), "status": .string("failed")]),
    ]))
  }

  @Test
  func `a clear gate still says what is worth saying about the workspace, under its line`(
  ) async {
    await workspace.recordEverythingPassing()

    let result = await workspace.run(["status", "--gate", "--group", "release"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first == "gate: clear")
    #expect(
      result.outputLines.dropFirst().first
        == "warning: use-case-groups.yml: group 'nothing-yet' has no members",
    )
  }

  @Test
  func `a blocked gate says it under the gate line and before the hint`() async {
    await workspace.record("shop.cart.add", "fail")

    let lines = await workspace.run(["status", "--gate", "--group", "cart"]).outputLines
    let gate = lines.firstIndex { line in
      line.hasPrefix("gate: blocked")
    }
    let warning = lines.firstIndex { line in
      line.hasPrefix("warning: use-case-groups.yml: group 'nothing-yet'")
    }

    #expect(gate != nil)
    #expect(warning == gate.map { $0 + 1 })
    #expect(lines.last == "→ use-cases status shop.cart.add")
  }

  @Test
  func `strict applies to the members of the group`() async {
    await workspace.recordEverythingPassing()
    await workspace.record("shop.cart.add", "incomplete")

    let release = await workspace.run(["status", "--gate", "--strict", "--group", "release"])
    let cart = await workspace.run(["status", "--gate", "--strict", "--group", "cart"])

    #expect(release.exitCode == 0)
    #expect(release.standardOutput.contains("clear"))
    #expect(cart.exitCode == 1)
  }

  // @use-case:gate.strict#swift-tests.no-state-filter
  @Test
  func `the gate cannot be narrowed by a state or a target, though a group is allowed`(
  ) async {
    let withState = await workspace.run([
      "status",
      "--gate",
      "--group",
      "cart",
      "--state",
      "failed",
    ])
    let withTarget = await workspace.run(["status", "--gate", "--group", "cart", "shop.cart"])

    #expect(withState.exitCode == 2)
    #expect(withTarget.exitCode == 2)
  }

  // @use-case:end gate.strict#swift-tests.no-state-filter

  @Test
  func `a group name is matched exactly`() async {
    let result = await workspace.run(["status", "--group", "Release"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no group 'Release'"))
    #expect(result.standardError.contains("release"))
  }
}
