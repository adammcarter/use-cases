import Foundation
import Testing
@testable import UseCasesCLI

struct RecordCommandTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  private func run(_ arguments: [String]) async -> CommandResult {
    await workspace.run(arguments)
  }

  private func lines(_ result: CommandResult) -> [String] {
    result.standardOutput.split(separator: "\n").map(String.init)
  }

  // MARK: - Recording

  @Test
  func `a verdict is recorded and told in one line, then the hint to look at the use case`() async {
    let result = await run(["record", "shop.pay.card", "unit-tests", "pass"])

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(
      lines(result) == [
        "recorded: shop.pay.card / unit-tests → pass",
        "→ use-cases status shop.pay.card",
      ],
    )
  }

  @Test
  func `quiet leaves out the hint`() async {
    let result = await run(["record", "shop.pay.card", "unit-tests", "fail", "--quiet"])

    #expect(lines(result) == ["recorded: shop.pay.card / unit-tests → fail"])
  }

  @Test(arguments: ["pass", "fail", "incomplete", "error"])
  func `every status is recorded`(status: String) async {
    let result = await run(["record", "shop.pay.card", "unit-tests", status])

    #expect(result.exitCode == 0)
    #expect(lines(result).first == "recorded: shop.pay.card / unit-tests → \(status)")
  }

  @Test
  func `the run is sealed in the store with the verdict, its note and no links`() async throws {
    let result = await run([
      "--json",
      "record",
      "shop.pay.card",
      "unit-tests",
      "pass",
      "checked on staging",
    ])
    let document = try result.document()
    guard case let .string(identifier)? = document["run_id"] else {
      Issue.record("no run_id")
      return
    }
    let folder = ".use-cases/runs/\(identifier)"

    let log = try workspace.read("\(folder)/results.jsonl")

    #expect(workspace.hasStore)
    #expect(log.hasSuffix("}\n"))
    #expect(log.contains("\"message\":\"checked on staging\""))
    #expect(log.contains("\"via\":[\"record\"]"))
    #expect(!log.contains("\"links\""))
    #expect(try workspace.read("\(folder)/completion.json").contains("\"result_count\": 1"))
    #expect(try workspace.read(".use-cases/run-order.json").contains(identifier))
  }

  @Test
  func `an empty note is no note`() async throws {
    let document = try await run(["--json", "record", "shop.pay.card", "unit-tests", "pass", ""])
      .document()

    guard case let .array(results)? = document["results"], let result = results.first else {
      Issue.record("no results")
      return
    }

    #expect(result["message"] == nil)
  }

  @Test
  func `a second verdict is a new run with a greater id`() async throws {
    let first = try await run(["--json", "record", "shop.pay.card", "unit-tests", "fail"])
      .document()
    let second = try await run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])
      .document()

    guard case let .string(one)? = first["run_id"], case let .string(two)? = second["run_id"] else {
      Issue.record("no run ids")
      return
    }

    #expect(one < two)
  }

  @Test
  func `the same route records the same fingerprint until the code changes`() async throws {
    let before = try await run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])
      .document()
    let again = try await run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])
      .document()
    try workspace.folder.write(
      "src/a.swift",
      LinksWorkspace.marked("shop.pay.card#unit-tests.charges"),
    )
    let after = try await run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])
      .document()

    func fingerprint(_ document: JSONValue) -> JSONValue? {
      guard case let .array(results)? = document["results"] else {
        return nil
      }

      return results.first?["fingerprint"]
    }

    #expect(fingerprint(before) != nil)
    #expect(fingerprint(before) == fingerprint(again))
    #expect(fingerprint(before) != fingerprint(after))
  }

  // @use-case:record.by-hand#swift-tests.prefix
  @Test
  func `the start of one use case id names it`() async {
    let result = await run(["record", "shop.pay.c", "unit-tests", "pass", "--quiet"])

    #expect(lines(result) == ["recorded: shop.pay.card / unit-tests → pass"])
  }

  // @use-case:end record.by-hand#swift-tests.prefix

  @Test
  func `an id that is also the start of others is that use case alone`() async {
    let result = await run(["record", "shop.pay", "unit-tests", "pass", "--quiet"])

    #expect(lines(result) == ["recorded: shop.pay / unit-tests → pass"])
  }

  // @use-case:record.by-hand#swift-tests.prefix
  @Test
  func `the start of several ids is a usage refusal that lists them`() async throws {
    let result = await run(["--json", "record", "shop.pay.", "unit-tests", "pass"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(result.standardError.contains("shop.pay.card, shop.pay.wallet"))
    #expect(!workspace.hasStore)
  }

  // @use-case:end record.by-hand#swift-tests.prefix

  // MARK: - Refusals

  @Test(arguments: [
    (["record"], "missing: use case, route, status"),
    (["record", "shop.pay.card"], "missing: route, status"),
    (["record", "shop.pay.card", "unit-tests"], "missing: status"),
  ])
  func `too few values name what is missing and offer to ask`(
    arguments: [String],
    missing: String,
  ) async {
    let result = await run(arguments)
    let errorLines = result.standardError.split(separator: "\n").map(String.init)

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(errorLines.first == "error: record needs <use case> <route> <status>; \(missing)")
    #expect(errorLines.last == "→ use-cases record --interactive   to be asked for each")
    #expect(!workspace.hasStore)
  }

  @Test
  func `the hint is for people: a script's message and quiet runs have none`() async throws {
    let scripted = await run(["--json", "record", "shop.pay.card"])
    let quiet = await run(["record", "shop.pay.card", "--quiet"])
    let message = try scripted.document()["error"]?["message"]

    #expect(scripted.exitCode == 2)
    #expect(try scripted.document()["error"]?["kind"] == .string("usage"))
    #expect(message == .string("record needs <use case> <route> <status>; missing: route, status"))
    #expect(!scripted.standardError.contains("→"))
    #expect(!quiet.standardError.contains("→"))
  }

  @Test(arguments: ["verified", "PASS", "skip"])
  func `a status the store does not keep is a usage refusal`(status: String) async throws {
    let result = await run(["--json", "record", "shop.pay.card", "unit-tests", status])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(result.standardError.contains("status must be one of"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a route that is not there is a usage refusal that says so`() async throws {
    let result = await run(["--json", "record", "shop.pay.card", "nope", "pass"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(result.standardError == "error: no route shop.pay.card / nope\n")
    #expect(!workspace.hasStore)
  }

  @Test
  func `a use case that is not there is a usage refusal`() async throws {
    let result = await run(["--json", "record", "shop.nope", "unit-tests", "pass"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a DRAFT use case is refused as something that cannot proceed now`() async throws {
    try workspace.folder.write(
      "use-cases/wip.yml",
      """
      use_cases:
        - id: wip
          title: Not finished
          value_tier: core
          scenarios:
            - id: works
              when: [x]
              then: [y]
          validation:
            - id: unit-tests
              type: { kind: unit }
              covers: [works]

      """,
    )

    let result = await run(["--json", "record", "shop.wip", "unit-tests", "pass"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(result.standardError.contains("shop.wip is DRAFT"))
    #expect(result.standardError.contains("missing intent"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a workspace made INVALID by a link is refused as invalid, writing nothing`() async throws {
    try workspace.folder.write("src/a.swift", "// \(MarkerText.sentinel)shop.pay#top\nwork()\n")

    let result = await run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a store that cannot be written is a storage refusal`() async throws {
    try workspace.folder.write(".use-cases", "not a folder")

    let result = await run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("storage"))
  }

  // MARK: - Interactive and attach

  @Test
  func `interactive needs a terminal, and says so whatever else is on the line`() async throws {
    let human = await run(["record", "--interactive"])
    let scripted = await run(["--json", "record", "--interactive"])
    let both = await workspace.run(
      ["--json", "record", "--interactive"],
      isTerminal: true,
    )

    #expect(human.exitCode == 2)
    #expect(human.standardError.hasPrefix("error: record --interactive needs a terminal"))
    #expect(scripted.exitCode == 2)
    #expect(try scripted.document()["error"]?["kind"] == .string("usage"))
    #expect(both.exitCode == 2)
    #expect(!workspace.hasStore)
  }

  @Test
  func `interactive without a terminal never waits for input`() async {
    let prompter = MockPrompter(answers: ["shop.pay.card"])

    let result = await workspace.run(
      ["record", "--interactive", "shop.pay.card"],
      prompter: prompter,
    )

    #expect(result.exitCode == 2)
    #expect(await prompter.transcript.isEmpty)
  }
}
