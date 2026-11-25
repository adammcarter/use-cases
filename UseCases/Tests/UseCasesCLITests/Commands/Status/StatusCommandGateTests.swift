import Foundation
import Testing
@testable import UseCasesCLI

struct StatusCommandGateTests {
  private struct GateItem {
    let useCase: String
    let status: String
    let approval: String?
  }

  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func gate(
    _ extra: [String] = [],
    exitCode: Int32,
    in workspace: StatusWorkspace? = nil,
  ) async throws -> [String: [GateItem]] {
    let result = await ((workspace ?? self.workspace).run(["--json", "status", "--gate"] + extra))
    let answer = try #require(try result.document()["gate"])

    #expect(result.exitCode == exitCode)

    return [
      "blocking": entries(answer["blocking"]),
      "warning": entries(answer["warning"]),
    ]
  }

  private func entries(_ value: JSONValue?) -> [GateItem] {
    guard case let .array(items)? = value else {
      return []
    }

    return items.compactMap { item in
      guard case let .string(useCase)? = item["use_case"],
            case let .string(status)? = item["status"]
      else {
        return nil
      }

      var approval: String?

      if case let .string(held)? = item["approval"] {
        approval = held
      }

      return GateItem(
        useCase: useCase,
        status: status,
        approval: approval,
      )
    }
  }

  // MARK: - The table

  @Test
  func `by default failed, error and stale block and the rest warn`() async throws {
    try await workspace.recordEveryState()

    let answer = try await gate(exitCode: 1)

    #expect(answer["blocking"]?.map(\.useCase) == [
      "shop.pay.card",
      "shop.pay.wallet",
      "shop.pay.refund",
    ])
    #expect(answer["blocking"]?.map(\.status) == ["failed", "error", "stale"])
    #expect(answer["warning"]?.map(\.useCase) == ["shop.pay.voucher", "shop.pay.gift"])
    #expect(answer["warning"]?.map(\.status) == ["incomplete", "unverified"])
  }

  @Test
  func `strict blocks everything not verified, and never a draft`() async throws {
    try await workspace.recordEveryState()

    let answer = try await gate(["--strict"], exitCode: 1)

    #expect(
      Set(answer["blocking"]?.map(\.useCase) ?? [])
        == [
          "shop.pay.card",
          "shop.pay.wallet",
          "shop.pay.refund",
          "shop.pay.voucher",
          "shop.pay.gift",
        ],
    )
    #expect(answer["warning"]?.isEmpty == true)
  }

  @Test(arguments: [("fail", true), ("error", true), ("incomplete", false)])
  func `each state on its own`(
    verdict: String,
    blocks: Bool,
  ) async {
    await workspace.recordEverythingPassing()
    await workspace.record("shop.pay.card", verdict)

    let result = await workspace.run(["--json", "status", "--gate"])

    #expect(result.exitCode == (blocks ? 1 : 0))
  }

  @Test
  func `stale alone blocks, and a clean workspace passes even strictly`() async throws {
    await workspace.recordEverythingPassing()
    #expect(try await gate(["--strict"], exitCode: 0)["blocking"]?.isEmpty == true)

    try workspace.editIntent(of: "card")
    let answer = try await gate(exitCode: 1)

    #expect(answer["blocking"]?.count == 1)
    #expect(answer["blocking"]?.first?.useCase == "shop.pay.card")
    #expect(answer["blocking"]?.first?.status == "stale")
    #expect(answer["blocking"]?.first?.approval == nil)
  }

  @Test
  func `a failing route that does not gate never blocks`() async throws {
    await workspace.recordEverythingPassing()
    await workspace.record("shop.pay.card", "fail", route: "extra")

    _ = try await gate(["--strict"], exitCode: 0)
  }

  @Test
  func `the json document is the status document with the gate in it`() async throws {
    try await workspace.recordEveryState()

    let document = try await workspace.run(["--json", "status", "--gate"]).document()
    let schema = try PublishedSchema(path: "schemas/output/cli-status.schema.json")

    #expect(try schema.failures(of: document) == [])
    #expect(document["gate"]?["passed"] == .boolean(false))
    #expect(document["gate"]?["strict"] == .boolean(false))
  }

  // MARK: - What people read

  @Test
  func `people see what blocks, what warns and why`() async throws {
    try await workspace.recordEveryState()

    let result = await workspace.run(["status", "--gate"])
    let output = result.outputLines

    #expect(result.exitCode == 1)
    #expect(output[0].hasPrefix("✗ failed      shop.pay.card"))
    #expect(output[1].hasPrefix("! error       shop.pay.wallet"))
    #expect(output[2].hasPrefix("◐ incomplete  shop.pay.voucher"))
    #expect(output[2].hasSuffix("(warning)"))
    #expect(output[3].hasPrefix("○ unverified  shop.pay.gift"))
    #expect(output[3].hasSuffix("(warning)"))
    #expect(output[4].hasPrefix("~ stale       shop.pay.refund"))
    #expect(!output[4].hasSuffix("(warning)"))
    #expect(output[5].isEmpty)
    #expect(
      output[6]
        == "gate: blocked · 3 block (1 failed, 1 error, 1 stale) "
        + "· 2 warnings (1 incomplete, 1 unverified)",
    )
    #expect(output[7] == "→ use-cases status shop.pay.card")
    #expect(output.count == 8)
  }

  @Test
  func `strict says so in the line`() async throws {
    try await workspace.recordEveryState()

    let output = await workspace.run(["status", "--gate", "--strict"]).outputLines

    #expect(
      output.contains(
        "gate (strict): blocked · 5 block (1 failed, 1 error, 1 incomplete, 1 unverified, 1 stale)",
      ),
    )
  }

  @Test
  func `a clear gate says so and has no hint`() async {
    await workspace.recordEverythingPassing()

    let result = await workspace.run(["status", "--gate"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines == ["gate: clear"])
  }

  @Test
  func `warnings alone leave the gate clear and are still told`() async {
    await workspace.recordEverythingPassing()
    await workspace.record("shop.pay.card", "incomplete")

    let result = await workspace.run(["status", "--gate"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.last == "gate: clear · 1 warning (1 incomplete)")
  }

  @Test
  func `quiet takes the hint out`() async throws {
    try await workspace.recordEveryState()

    #expect(await !(workspace.run(["status", "--gate", "--quiet"])).standardOutput.contains("→"))
  }

  // MARK: - Sign-off

  private func signOff() async throws -> StatusWorkspace {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )
    await required.recordEverythingPassing()

    return required
  }

  @Test
  func `without sign-off required approvals never gate`() async throws {
    await workspace.recordEverythingPassing()

    let answer = try await gate(["--strict"], exitCode: 0)

    #expect(answer["blocking"]?.isEmpty == true)
    #expect(answer["warning"]?.isEmpty == true)
  }

  @Test
  func `a critical use case not approved blocks by default while the others warn`() async throws {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )
    let cart = try String(
      contentsOf: required.folder.url.appendingPathComponent("use-cases/cart.yml"),
      encoding: .utf8,
    )
    try required.folder.write(
      "use-cases/cart.yml",
      cart.replacingOccurrences(
        of: "value_tier: core",
        with: "value_tier: critical",
      ),
    )
    await required.recordEverythingPassing()

    let result = await required.run(["status", "--gate"])

    #expect(result.exitCode == 1)
    #expect(result.outputLines
      .contains("gate: blocked · 1 block (1 not approved) · 5 warnings (5 not approved)"))
    #expect(result.outputLines.last == "→ use-cases status shop.cart.add")
  }

  @Test
  func `people see why the gate holds`() async throws {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )
    await required.recordEverythingPassing()

    let result = await required.run(["status", "--gate", "--strict"])
    let output = result.outputLines

    #expect(result.exitCode == 1)
    #expect(
      output.contains { line in
        line.hasPrefix("✓ verified    shop.cart.add") && line.hasSuffix("(not approved)")
      },
    )
    #expect(output.contains("gate (strict): blocked · 6 block (6 not approved)"))
    #expect(output.last == "→ use-cases status shop.cart.add")
  }

  @Test
  func `core use cases that are not approved only warn by default`() async throws {
    let required = try await signOff()

    let result = await required.run(["status", "--gate"])
    let output = result.outputLines

    #expect(result.exitCode == 0)
    #expect(output
      .contains {
        $0.hasPrefix("✓ verified    shop.cart.add") && $0.hasSuffix("(warning: not approved)")
      })
    #expect(output.last == "gate: clear · 6 warnings (6 not approved)")
  }

  @Test
  func `a gate entry held for sign-off says which kind of hold it is`() async throws {
    let required = try await signOff()

    let answer = try await gate(["--strict"], exitCode: 1, in: required)

    #expect(answer["blocking"]?.count == 6)
    #expect(answer["blocking"]?
      .allSatisfy { $0.status == "verified" && $0.approval == "unapproved" } == true)
  }

  // MARK: - Said once

  @Test
  func `an unverified use case not approved says both when it only warns`() async throws {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )
    await required.record("shop.cart.add", "pass")

    let output = await required.run(["status", "--gate"]).outputLines

    #expect(
      output.contains { line in
        line.hasPrefix("○ unverified  shop.pay.card") && line.hasSuffix("(warning: not approved)")
      },
    )
    #expect(output.last == "gate: clear · 6 warnings (5 unverified, 1 not approved)")
  }

  @Test
  func `a promise changed since its sign-off is said once`() async throws {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )
    let cart = try String(
      contentsOf: required.folder.url.appendingPathComponent("use-cases/cart.yml"),
      encoding: .utf8,
    )
    try required.folder.write(
      "use-cases/cart.yml",
      cart.replacingOccurrences(
        of: "value_tier: core",
        with: "value_tier: critical",
      ) + "    approved:\n      by: Sam\n      \"on\": \"2026-10-19\"\n"
        + "      behaviour: \(String(repeating: "a", count: 64))\n",
    )
    await required.recordEverythingPassing()

    let result = await required.run(["status", "--gate"])
    let line = try #require(
      result.outputLines.first { line in
        line.contains("shop.cart.add")
      },
    )

    #expect(result.exitCode == 1)
    #expect(line.hasSuffix("changed since approved"))
    #expect(!line.contains("(not approved)"))
    #expect(
      result.outputLines.contains { line in
        line.hasPrefix("gate: blocked · 1 block (1 not approved)")
      },
    )
  }
}
