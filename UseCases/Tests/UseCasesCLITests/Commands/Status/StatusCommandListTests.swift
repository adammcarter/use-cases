import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCLI

struct StatusCommandListTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func lines(_ arguments: [String]) async -> [String] {
    await workspace.run(arguments).outputLines
  }

  private func identifiers(_ arguments: [String]) async throws -> [String] {
    let document = try await workspace.run(["--json"] + arguments).document()

    guard case let .array(useCases)? = document["use_cases"] else {
      Issue.record("no use_cases")
      return []
    }

    return useCases.compactMap { useCase in
      guard case let .string(identifier)? = useCase["use_case"] else {
        return nil
      }

      return identifier
    }
  }

  // MARK: - A checkout where nothing has run

  @Test
  func `a checkout where nothing has run says so in one line and offers a baseline`() async {
    let result = await workspace.run(["status"])

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(
      await lines(["status"]) == [
        "no verdicts in this checkout yet: 6 use cases (1 draft), none run here",
        "→ use-cases verify --start   for a baseline, if you want one",
      ],
    )
  }

  @Test
  func `the one line is left once anything has been recorded`() async {
    await workspace.record("shop.cart.add", "pass")

    let text = await workspace.run(["status"]).standardOutput

    #expect(!text.contains("no verdicts in this checkout"))
    #expect(text.contains("shop.pay.card"))
  }

  @Test
  func `quiet takes the hint out of the one line`() async {
    #expect(
      await lines(["status", "--quiet"]) == [
        "no verdicts in this checkout yet: 6 use cases (1 draft), none run here",
      ],
    )
  }

  @Test(arguments: [
    ["status", "--state", "unverified"],
    ["status", "shop.pay"],
    ["status", "shop.pay.card"],
    ["--json", "status"],
  ])
  func `a filtered or detailed view and json list as usual`(arguments: [String]) async {
    let text = await workspace.run(arguments).standardOutput

    #expect(!text.contains("no verdicts in this checkout"))
    #expect(text.contains("shop.pay.card"))
  }

  // MARK: - Order, summary and filters

  @Test
  func `use cases are listed worst first, then drafts, with the summary and one hint`(
  ) async throws {
    try await workspace.recordEveryState()

    let output = await lines(["status"])

    #expect(output.count == 11)
    #expect(output[0].hasPrefix("✗ failed      shop.pay.card"))
    #expect(output[0].hasSuffix("check failed (run \(runPrefix(output[0])) via record)"))
    #expect(output[1].hasPrefix("! error       shop.pay.wallet"))
    #expect(output[2].hasPrefix("◐ incomplete  shop.pay.voucher"))
    #expect(output[3].hasPrefix("○ unverified  shop.pay.gift"))
    #expect(output[3].hasSuffix("check: no verdict yet"))
    #expect(output[4].hasPrefix("~ stale       shop.pay.refund"))
    #expect(output[4].contains("check: changed since run "))
    #expect(output[5] == "✓ verified    shop.cart.add")
    #expect(output[6].hasPrefix("· draft       shop.cart.share"))
    #expect(output[6].hasSuffix("missing: value_tier"))
    #expect(output[7].isEmpty)
    #expect(
      output[8]
        == "7 use cases · 1 failed · 1 error · 1 incomplete · 1 unverified · 1 stale "
        + "· 1 verified · 1 draft",
    )
    #expect(output[9].hasPrefix("results: 6 runs · "))
    #expect(output[10] == "→ use-cases status shop.pay.card   to see why")
    #expect(
      output.count { line in
        line.hasPrefix("→")
      } == 1,
    )
  }

  private func runPrefix(_ line: String) -> String {
    guard let range = line.range(of: "run ") else {
      return ""
    }

    return String(line[range.upperBound...].prefix(8))
  }

  @Test
  func `the reasons line up`() async throws {
    try await workspace.recordEveryState()

    let output = await lines(["status"])
    let columns = output.prefix(5).map { line in
      line.range(of: "check")?.lowerBound.utf16Offset(in: line)
    }

    #expect(Set(columns).count == 1)
  }

  @Test
  func `with only stale use cases the hint points at verify`() async throws {
    await workspace.recordEverythingPassing()
    try workspace.editIntent(of: "card")

    let output = await lines(["status"])

    #expect(output[0].hasPrefix("~ stale       shop.pay.card"))
    #expect(output.last == "→ use-cases verify --start")
  }

  @Test
  func `quiet and json have no hint`() async throws {
    try await workspace.recordEveryState()

    #expect(await !(workspace.run(["status", "--quiet"])).standardOutput.contains("→"))
    #expect(await !(workspace.run(["status", "--json"])).standardOutput.contains("→"))
  }

  @Test
  func `state keeps only those states, and draft is a state`() async throws {
    try await workspace.recordEveryState()

    #expect(try await identifiers(["status", "--state", "failed,stale"]) == [
      "shop.pay.card",
      "shop.pay.refund",
    ])
    #expect(try await identifiers(["status", "--state", "draft"]) == ["shop.cart.share"])
    #expect(try await identifiers(["status", "--state", "verified, draft"]) == [
      "shop.cart.add",
      "shop.cart.share",
    ])
  }

  @Test
  func `a prefix narrows to the use cases under it, and filters combine`() async throws {
    try await workspace.recordEveryState()

    #expect(try await identifiers(["status", "shop.cart"]) == [
      "shop.cart.add",
      "shop.cart.share",
    ])
    #expect(try await identifiers(["status", "shop.pay", "--state", "stale"]) ==
      ["shop.pay.refund"])
  }

  @Test
  func `a summary counts only what is shown`() async throws {
    try await workspace.recordEveryState()

    let output = await lines(["status", "--state", "failed,stale"])

    #expect(output.last == "→ use-cases status shop.pay.card   to see why")
    #expect(output.contains("2 use cases · 1 failed · 1 stale"))
  }

  @Test
  func `a view with nothing in it says 0 use cases`() async {
    await workspace.record("shop.cart.add", "pass")

    let output = await lines(["status", "--state", "error"])

    #expect(output.contains("0 use cases"))
  }

  @Test
  func `the hint offers verify when only stale or unverified use cases are shown`() async {
    await workspace.record("shop.cart.add", "pass")

    #expect(await lines(["status", "--state", "unverified"]).last == "→ use-cases verify --start")
  }

  // MARK: - Warnings

  @Test(arguments: ["", "\n\n   \n"])
  func `an emptied marked region is said under the list and in the one line`(
    inside: String,
  ) async throws {
    try workspace.folder.write(
      "src/pay.py",
      "# \(MarkerText.sentinel)shop.pay.card#charge\n\(inside)"
        + "# \(MarkerText.sentinel)end shop.pay.card#charge\n",
    )
    let expected =
      "warning: shop.pay.card: src/pay.py:2: its marked region is empty; "
        + "if the code moved, move its markers with it"

    #expect(await lines(["status"]).contains(expected))

    await workspace.record("shop.cart.add", "pass")

    #expect(await lines(["status"]).contains(expected))
    #expect(await workspace.run(["status", "shop.pay.card"]).standardOutput
      .contains("its marked region is empty"))
  }

  @Test
  func `a marked region with code raises nothing`() async throws {
    try workspace.folder.write(
      "src/pay.py",
      "# \(MarkerText.sentinel)shop.pay.card#charge\ndef charge(): pass\n"
        + "# \(MarkerText.sentinel)end shop.pay.card#charge\n",
    )

    #expect(await !(workspace.run(["status"])).standardOutput.contains("marked region is empty"))
  }

  @Test
  func `missing links are told in the detail and in json, and not in the list`() async {
    await workspace.record("shop.cart.add", "pass")

    #expect(await !(workspace.run(["status"])).standardOutput.contains("no implementation links"))
    #expect(await workspace.run(["status", "shop.cart.add"]).standardOutput
      .contains("no implementation links"))
    #expect(await workspace.run(["--json", "status"]).standardOutput
      .contains("no implementation links"))
  }

  @Test
  func `a run that never finished is a warning under the list, in short`() async throws {
    await workspace.record("shop.cart.add", "pass")
    let document = try await workspace.run(["--json", "record", "shop.cart.add", "check", "pass"])
      .document()
    guard case let .string(identifier)? = document["run_id"] else {
      Issue.record("no run_id")
      return
    }
    try FileManager.default.removeItem(
      at: workspace.folder.url
        .appendingPathComponent(".use-cases/runs/\(identifier)/completion.json"),
    )

    let human = await lines(["status"])
    let scripted = await workspace.run(["--json", "status"]).standardOutput

    #expect(human.contains("warning: run \(identifier.prefix(8)) never finished"))
    #expect(scripted.contains("run \(identifier) never finished"))
  }

  // MARK: - Where verdicts come from

  @Test
  func `where a validation has a run command the hints offer verify run`() async throws {
    try workspace.folder.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)

    #expect(
      await lines(["status"])
        .last == "→ use-cases verify --run   for a baseline, if you want one",
    )

    await workspace.record("shop.cart.add", "pass")

    #expect(await lines(["status"]).last == "→ use-cases verify --run")
  }

  @Test
  func `where no validation has one they offer verify start`() async throws {
    try workspace.folder.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(transformer: "exit-code"),
    )
    await workspace.record("shop.cart.add", "pass")

    #expect(await lines(["status"]).last == "→ use-cases verify --start")
  }
}
