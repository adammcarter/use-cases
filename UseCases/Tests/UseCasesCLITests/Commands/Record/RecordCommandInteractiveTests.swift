import Foundation
import Testing
@testable import UseCasesCLI

struct RecordCommandInteractiveTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  /// A person at a terminal who types these answers.
  private func interview(
    _ answers: [String],
    extra: [String] = [],
  ) async -> (result: CommandResult, prompter: MockPrompter) {
    let prompter = MockPrompter(answers: answers)
    let result = await workspace.run(
      ["record", "--interactive"] + extra,
      isTerminal: true,
      prompter: prompter,
    )

    return (result, prompter)
  }

  private func lines(_ result: CommandResult) -> [String] {
    result.standardOutput.split(separator: "\n").map(String.init)
  }

  // MARK: - Asking

  @Test
  func `each value is asked for in turn, and the verdict is recorded as if it were given`() async {
    let (result, prompter) = await interview(["shop.pay.card", "unit-tests", "pass", "on staging"])

    #expect(result.exitCode == 0)
    #expect(
      lines(result) == [
        "recorded: shop.pay.card / unit-tests → pass",
        "→ use-cases status shop.pay.card",
      ],
    )
    #expect(
      await prompter.transcript == [
        "Use case?  1 shop.cart.add   2 shop.cart.share   3 shop.pay.card"
          + "   4 shop.pay.wallet   5 shop.pay",
        "           > ",
        "Route?     1 unit-tests",
        "           > ",
        "Result?    pass / fail / incomplete / error",
        "           > ",
        "Note?      (optional) > ",
      ],
    )
  }

  @Test
  func `the note goes into the log, and an empty one is no note`() async throws {
    let noted = await interview(["shop.pay.card", "unit-tests", "fail", "  broke on staging  "])
    let bare = await interview(["shop.pay.card", "unit-tests", "pass", ""])

    let first = try workspace.read(".use-cases/runs/\(runs()[0])/results.jsonl")
    let second = try workspace.read(".use-cases/runs/\(runs()[1])/results.jsonl")

    #expect(noted.result.exitCode == 0)
    #expect(bare.result.exitCode == 0)
    #expect(first.contains("\"message\":\"broke on staging\""))
    #expect(!second.contains("message"))
  }

  @Test(arguments: [
    ["3", "1", "pass", ""],
    ["shop.pay.c", "unit-tests", "pass", ""],
    ["shop.pay.card", "unit", "pass", ""],
    ["shop.pay.card", "1", "pass", ""],
  ])
  func `a use case and a route may be given by number, id or the start of an id`(
    answers: [String],
  ) async {
    let (result, _) = await interview(answers)

    #expect(lines(result).first == "recorded: shop.pay.card / unit-tests → pass")
  }

  @Test
  func `only READY use cases are offered`() async throws {
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

    let (_, prompter) = await interview([])

    let shown = try #require(await prompter.transcript.first)
    #expect(!shown.contains("shop.wip"))
  }

  @Test
  func `a route's steps are shown when it has them`() async throws {
    try workspace.folder.write(
      "use-cases/walk.yml",
      """
      use_cases:
        - id: walk
          title: Walk it
          value_tier: core
          intent: Someone walks it.
          scenarios:
            - id: works
              when: [x]
              then: [y]
          validation:
            - id: by-hand
              type: { kind: acceptance }
              covers: [works]
              procedure:
                steps: [Open it., Look at it.]

      """,
    )

    let (result, prompter) = await interview(["shop.walk", "by-hand", "pass", ""])

    #expect(result.exitCode == 0)
    #expect(
      await prompter.transcript.contains("           Steps: 1. Open it.  2. Look at it."),
    )
  }

  @Test
  func `attachments given with interactive are recorded`() async throws {
    let evidence = try TemporaryFolder()
    try evidence.write("shot.png", "x")

    let (result, _) = await interview(
      ["shop.pay.card", "unit-tests", "pass", ""],
      extra: ["--attach", evidence.url.appendingPathComponent("shot.png").path],
    )

    let run = try #require(runs().first)
    #expect(result.exitCode == 0)
    #expect(
      try workspace.read(".use-cases/runs/\(run)/results.jsonl").contains("\"name\":\"shot.png\""),
    )
  }

  // MARK: - Refusing

  @Test
  func `an ambiguous start is a usage refusal that lists the matches, not a second question`(
  ) async {
    let (result, prompter) = await interview(["shop.pay.", "unit-tests", "pass", ""])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("shop.pay.card, shop.pay.wallet"))
    #expect(await prompter.transcript.count == 2)
    #expect(!workspace.hasStore)
  }

  @Test
  func `an answer that names nothing is a usage refusal`() async {
    let (result, _) = await interview(["shop.nope"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use case or id prefix 'shop.nope'"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a route that is not offered is a usage refusal`() async {
    let (result, _) = await interview(["shop.pay.card", "9"])

    #expect(result.exitCode == 2)
    #expect(result.standardError == "error: no route shop.pay.card / 9\n")
    #expect(!workspace.hasStore)
  }

  @Test
  func `a result the store does not keep is a usage refusal`() async {
    let (result, _) = await interview(["shop.pay.card", "unit-tests", "maybe", ""])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("status must be one of"))
    #expect(!workspace.hasStore)
  }

  @Test(arguments: [
    [],
    ["shop.pay.card"],
    ["shop.pay.card", "unit-tests"],
    ["shop.pay.card", "unit-tests", "pass"]
  ])
  func `input that ends at any question is a refusal that writes nothing`(
    answers: [String],
  ) async {
    let (result, _) = await interview(answers)

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("input ended"))
    #expect(!workspace.hasStore)
  }

  @Test
  func `a value on the command line is refused: interactive asks for every one`() async {
    let (result, prompter) = await interview(
      ["shop.pay.card"],
      extra: ["shop.pay.card"],
    )
    let withNote = await interview(
      [],
      extra: ["a", "b", "pass", "note"],
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("asks for every value"))
    #expect(withNote.result.exitCode == 2)
    #expect(await prompter.transcript.isEmpty)
    #expect(!workspace.hasStore)
  }

  @Test
  func `a file that is not there is refused before the first question`() async {
    let (result, prompter) = await interview(
      ["shop.pay.card", "unit-tests", "pass", ""],
      extra: ["--attach", "/nowhere/shot.png"],
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("/nowhere/shot.png"))
    #expect(await prompter.transcript.isEmpty)
    #expect(!workspace.hasStore)
  }

  @Test
  func `a workspace that is INVALID is refused before the first question`() async throws {
    try workspace.folder.write("src/a.swift", "// @use-case:shop.pay#top\nwork()\n")

    let (result, prompter) = await interview(["shop.pay.card", "unit-tests", "pass", ""])

    #expect(result.exitCode == 2)
    #expect(await prompter.transcript.isEmpty)
    #expect(!workspace.hasStore)
  }

  private func runs() throws -> [String] {
    try FileManager.default
      .contentsOfDirectory(atPath: workspace.folder.url.appendingPathComponent(".use-cases/runs")
        .path)
      .sorted()
  }
}
