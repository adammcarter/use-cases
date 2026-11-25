import Foundation
import Testing
@testable import UseCasesCLI

struct StatusCommandDetailTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func lines(_ arguments: [String]) async -> [String] {
    await workspace.run(arguments).outputLines
  }

  @Test
  func `an exact id shows every route, whether it gates, its state and why`() async throws {
    try await workspace.recordEveryState()

    let output = await lines(["status", "shop.pay.card"])

    #expect(output[0] == "✗ failed  shop.pay.card · Card")
    #expect(output[2].hasPrefix("  route"))
    #expect(output[2].contains("gates"))
    #expect(output[3].hasPrefix("  check"))
    #expect(output[3].contains("yes"))
    #expect(output[3].contains("✗ failed"))
    #expect(output[3].contains(" via record"))
    #expect(output[4].hasPrefix("  extra"))
    #expect(output[4].contains("no "))
    #expect(output[4].contains("✓ verified"))
    #expect(output.last == "→ use-cases verify --start   once it is fixed")
  }

  @Test
  func `a run that shares its first digits with another run is shown by the shortest prefix`()
    async throws
  {
    await workspace.record("shop.pay.card", "fail")
    let run = try workspace.onlyRun()
    try workspace.plantUnfinishedRun(StatusWorkspace.neighbour(of: run, sharing: 10))

    let output = await lines(["status", "shop.pay.card"])

    #expect(output[3].hasSuffix("run \(run.prefix(11)) via record"))
  }

  @Test
  func `a stale use case says what it changed since`() async throws {
    try await workspace.recordEveryState()

    let text = await workspace.run(["status", "shop.pay.refund"]).standardOutput

    #expect(text.hasPrefix("~ stale  shop.pay.refund"))
    #expect(text.contains("changed since run "))
    #expect(text.hasSuffix("→ use-cases verify --start\n"))
  }

  @Test
  func `a route nobody has run has no verdict yet`() async {
    let text = await workspace.run(["status", "shop.pay.gift"]).standardOutput

    #expect(text.contains("○ unverified"))
    #expect(text.contains("no verdict yet"))
  }

  @Test
  func `a draft says what it lacks and has no table`() async {
    let output = await lines(["status", "shop.cart.share"])

    #expect(output[0] == "· draft  shop.cart.share · Share")
    #expect(output.contains("missing: value_tier"))
    #expect(
      !output.contains { line in
        line.contains("route")
      },
    )
  }

  @Test
  func `an exact id that is also a prefix is that use case alone`() async throws {
    try workspace.folder.write(
      "use-cases/top.yml",
      "use_cases:\n  - id: pay\n    title: Pay\n    value_tier: core\n    intent: pay.\n"
        + "    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
        + "    validation:\n      - id: check\n        type: { kind: acceptance }\n"
        + "        covers: [s]\n        procedure:\n          steps: [Check it.]\n",
    )

    let output = await lines(["status", "shop.pay"])

    #expect(output[0].contains("shop.pay · Pay"))
    #expect(!output.joined().contains("shop.pay.card"))
  }

  @Test
  func `the detail of a verified use case has no hint`() async {
    await workspace.record("shop.cart.add", "pass")

    let output = await lines(["status", "shop.cart.add"])

    #expect(output[0] == "✓ verified  shop.cart.add · Add")
    #expect(
      !output.contains { line in
        line.hasPrefix("→")
      },
    )
  }

  @Test
  func `quiet takes the hint out of the detail`() async {
    #expect(await !(workspace.run(["status", "shop.pay.gift", "--quiet"])).standardOutput
      .contains("→"))
  }

  @Test
  func `missing links are warnings of the use case in its detail`() async {
    let text = await workspace.run(["status", "shop.cart.add"]).standardOutput

    #expect(text.contains("warning: no implementation links"))
  }

  @Test
  func `a route with a procedure and no links is not warned about`() async {
    let text = await workspace.run(["status", "shop.cart.add"]).standardOutput

    #expect(!text.contains("only `use-cases record` can verify it"))
  }

  @Test
  func `a route with neither links nor a procedure is`() async throws {
    try workspace.folder.write(
      "use-cases/solo.yml",
      "use_cases:\n  - id: solo\n    title: Solo\n    value_tier: core\n    intent: solo.\n"
        + "    scenarios:\n      - id: s\n        when: [x]\n        then: [y]\n"
        + "    validation:\n      - id: unit\n        type: { kind: unit }\n        covers: [s]\n",
    )

    let text = await workspace.run(["status", "shop.solo"]).standardOutput

    #expect(text.contains("warning: route unit has no validation links and no procedure"))
    #expect(text.contains("only `use-cases record` can verify it"))
  }

  // MARK: - Sign-off

  @Test
  func `an unapproved use case says nothing of sign-off where it is not required`() async {
    #expect(await !(workspace.run(["status", "shop.pay.card"])).standardOutput.contains("sign-off"))
  }

  @Test
  func `where sign-off is required an unapproved use case says so`() async throws {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )

    #expect(await required.run(["status", "shop.pay.card"]).standardOutput
      .contains("sign-off: not approved"))
  }

  @Test
  func `a draft is never said to be not approved`() async throws {
    let required = try StatusWorkspace(
      root: "schema_version: 1\nroot: true\nprefix: shop\nsign_off: required\n",
    )

    #expect(await !(required.run(["status", "shop.cart.share"])).standardOutput
      .contains("sign-off"))
  }
}
