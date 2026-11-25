import Foundation
import Testing
@testable import UseCasesCLI

struct StatusCommandRefusalTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  @Test(arguments: [
    (["status", "--state", "broken"], "unknown: broken"),
    (["status", "--state", "failed,"], "unknown: an empty state;"),
    (["status", "shop.nope"], "no use case or id prefix"),
    (["status", "--gate", "--state", "failed"], "cannot be combined"),
    (["status", "shop.pay.card", "--gate"], "cannot be combined"),
    (["status", "--strict"], "--strict belongs with --gate"),
  ])
  func `a request that is wrong is a usage refusal that says why, to a person and to a script`(
    arguments: [String],
    message: String,
  ) async throws {
    let scripted = await workspace.run(["--json"] + arguments)
    let human = await workspace.run(arguments)
    let error = try #require(try scripted.document()["error"])

    #expect(scripted.exitCode == 2)
    #expect(error["kind"] == .string("usage"))
    #expect(scripted.standardError.contains(message))
    #expect(scripted.standardError.hasPrefix("error: "))
    #expect(human.exitCode == 2)
    #expect(human.standardOutput.isEmpty)
    #expect(try scripted.document()["command"] == .string("status"))
  }

  @Test
  func `an INVALID workspace is refused as invalid, for the gate too`() async throws {
    try workspace.folder.write(
      "use-cases/cart.yml",
      "prefix: cart\nuse_cases:\n  - id: add\n    title: Add\n    stray: true\n",
    )

    for arguments in [["status"], ["status", "--gate"]] {
      let result = await workspace.run(["--json"] + arguments)

      #expect(result.exitCode == 2)
      #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    }
  }

  @Test
  func `a workspace made INVALID by a link is refused as invalid`() async throws {
    try workspace.folder.write("src/a.swift", "// \(MarkerText.sentinel)shop.pay.card#a\nx\n")

    let result = await workspace.run(["--json", "status"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
  }

  @Test
  func `a resource that matches nothing is refused as invalid`() async throws {
    let cart = try String(
      contentsOf: workspace.folder.url.appendingPathComponent("use-cases/cart.yml"),
      encoding: .utf8,
    )
    try workspace.folder.write(
      "use-cases/cart.yml",
      cart.replacingOccurrences(
        of: "        covers: [s]\n",
        with: "        covers: [s]\n        resources:\n          - kind: file\n"
          + "            path: nope.json\n",
      ),
    )

    let result = await workspace.run(["--json", "status"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
  }

  // MARK: - A store that cannot be trusted

  @Test
  func `a stray entry in the store is a storage refusal that names it`() async throws {
    await workspace.record("shop.cart.add", "pass")
    try FileManager.default.createDirectory(
      at: workspace.folder.url.appendingPathComponent(".use-cases/runs/latest"),
      withIntermediateDirectories: true,
    )

    let result = await workspace.run(["--json", "status"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("storage"))
    #expect(result.standardError.contains("is not a run folder"))
    #expect(result.standardOutput.contains("is not a run folder"))
  }

  private static let tampered = [
    "results.jsonl": "\n",
    "run.json": "\n",
    "completion.json": "\"result_count\": 1",
  ]

  private static let tamperedTo = [
    "results.jsonl": " \n",
    "run.json": " \n",
    "completion.json": "\"result_count\": 0",
  ]

  @Test(arguments: ["results.jsonl", "run.json", "completion.json"])
  func `a tampered sealed run is a storage refusal, never skipped`(file: String) async throws {
    let document = try await workspace.run(["--json", "record", "shop.cart.add", "check", "fail"])
      .document()
    guard case let .string(identifier)? = document["run_id"] else {
      Issue.record("no run_id")
      return
    }
    let url = workspace.folder.url.appendingPathComponent(".use-cases/runs/\(identifier)/\(file)")
    let text = try String(contentsOf: url, encoding: .utf8)
    try Data(text.replacingOccurrences(
      of: Self.tampered[file] ?? "",
      with: Self.tamperedTo[file] ?? "",
    ).utf8)
      .write(to: url)

    let result = await workspace.run(["status"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("is corrupt"))
  }

  @Test
  func `every problem of the store is named`() async throws {
    for name in ["latest", "other"] {
      try FileManager.default.createDirectory(
        at: workspace.folder.url.appendingPathComponent(".use-cases/runs/\(name)"),
        withIntermediateDirectories: true,
      )
    }

    let result = await workspace.run(["status"])

    #expect(result.standardError.contains("latest is not a run folder"))
    #expect(result.standardError.contains("other is not a run folder"))
  }

  // MARK: - Groups

  @Test
  func `a group nobody wrote is a usage refusal, with no groups file at all`() async throws {
    let result = await workspace.run(["--json", "status", "--group", "release"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(result.standardError.contains("no group 'release'"))
  }

  @Test
  func `a target that names nothing is refused whatever the group`() async {
    let result = await workspace.run(["status", "shop.nope", "--group", "release"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use case or id prefix 'shop.nope'"))
  }

  @Test
  func `a groups file is not in the way unless a group is asked for`() async throws {
    await workspace.record("shop.cart.add", "pass")
    try workspace.folder.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  cart:\n    include: { prefixes: [shop.cart] }\n",
    )

    #expect(await workspace.run(["status"]).exitCode == 0)
    #expect(await workspace.run(["status", "--gate"]).standardOutput.contains("gate: clear"))
  }
}
