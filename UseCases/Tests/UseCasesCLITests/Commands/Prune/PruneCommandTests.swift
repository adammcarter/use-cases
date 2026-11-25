import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// `use-cases prune` (chapter 16 §20) on a real store, put there by `record`.
struct PruneCommandTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private var runsFolder: URL {
    workspace.folder.url.appendingPathComponent(".use-cases/runs")
  }

  private func runs() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: runsFolder.path).sorted()
  }

  /// Two verdicts for one route: the first run is superseded by the second.
  private func recordTwice() async throws -> (older: String, newer: String) {
    await workspace.record("shop.pay.card", "fail")
    await workspace.record("shop.pay.card", "pass")

    let found = try runs()

    return (found[0], found[1])
  }

  /// The document without what prune is allowed to change: the store's own line.
  private func withoutStore(_ document: JSONValue) -> JSONValue {
    guard case var .object(members) = document else {
      return document
    }

    members["store"] = nil

    return .object(members)
  }

  @Test
  func `a dry run names each superseded run in full and removes nothing`() async throws {
    let recorded = try await recordTwice()

    let result = await workspace.run(["prune", "--dry-run"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.count == 3)
    #expect(result.outputLines[0].hasPrefix("would remove  run \(recorded.older)  "))
    #expect(result.outputLines[1].isEmpty)
    #expect(result.outputLines[2].hasPrefix("would remove 1 run · would free "))
    #expect(try runs() == [recorded.older, recorded.newer])
  }

  @Test
  func `prune removes the superseded run, whole, and says how much it freed`() async throws {
    let recorded = try await recordTwice()

    let result = await workspace.run(["prune"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first?.hasPrefix("removed  run \(recorded.older)  ") == true)
    #expect(result.outputLines.last?.hasPrefix("removed 1 run · freed ") == true)
    #expect(try runs() == [recorded.newer])
  }

  @Test(arguments: [["status", "--json"], ["status", "--json", "--gate"]])
  func `no answer of status or the gate changes but the store's own line`(
    arguments: [String],
  ) async throws {
    try await workspace.recordEveryState()
    await workspace.record("shop.cart.add", "pass")
    await workspace.record("shop.pay.wallet", "error")

    let before = try await workspace.run(arguments).document()
    let pruned = await workspace.run(["prune"])
    let after = try await workspace.run(arguments).document()

    #expect(pruned.outputLines.count == 4)
    #expect(withoutStore(after) == withoutStore(before))

    if arguments.contains("--gate") {
      #expect(before["store"] == nil)
      #expect(after["store"] == nil)
    } else {
      #expect(before["store"] != after["store"])
    }
  }

  @Test
  func `a leftover of an interrupted prune is removed, and a dry run only names it`() async throws {
    await workspace.record("shop.pay.card", "pass")
    let name = ".tmp-prune-" + String(repeating: "1", count: 32)
    try workspace.folder.write(".use-cases/runs/\(name)/run.json", "{}\n")

    let preview = await workspace.run(["prune", "--dry-run"])
    let kept = try runs()
    let done = await workspace.run(["prune"])

    #expect(preview.outputLines.first == "would remove leftover  .use-cases/runs/\(name)  3 B")
    #expect(kept.contains(name))
    #expect(done.outputLines.first == "removed leftover  .use-cases/runs/\(name)  3 B")
    #expect(done.outputLines.last == "removed 1 leftover · freed 3 B")
    #expect(try !runs().contains(name))
  }

  @Test
  func `code back at an older state keeps the run that decides it now`() async throws {
    let path = "use-cases/pay.yml"
    let original = try String(
      contentsOf: workspace.folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
    await workspace.record("shop.pay.card", "pass")
    try workspace.editIntent(of: "card")
    await workspace.record("shop.pay.card", "fail")
    try workspace.folder.write(path, original)

    let before = try await workspace.run(["status", "--json"]).document()
    let gate = await workspace.run(["status", "--gate"]).exitCode
    let pruned = await workspace.run(["prune"])
    let after = try await workspace.run(["status", "--json"]).document()

    #expect(pruned.outputLines == ["nothing to prune"])
    #expect(try runs().count == 2)
    #expect(after == before)
    #expect(await workspace.run(["status", "--gate"]).exitCode == gate)
  }

  @Test
  func `nothing superseded says so, and an empty store too`() async throws {
    let empty = await workspace.run(["prune"])

    await workspace.record("shop.pay.card", "pass")
    await workspace.record("shop.pay.wallet", "pass")

    let kept = await workspace.run(["prune"])

    #expect(empty.outputLines == ["nothing to prune"])
    #expect(empty.exitCode == 0)
    #expect(kept.outputLines == ["nothing to prune"])
    #expect(try runs().count == 2)
  }

  @Test
  func `the json names each run and its size, and the total`() async throws {
    let recorded = try await recordTwice()

    let preview = try await workspace.run(["prune", "--json", "--dry-run"]).document()
    let done = try await workspace.run(["prune", "--json"]).document()

    #expect(preview["command"] == .string("prune"))
    #expect(preview["dry_run"] == .boolean(true))
    #expect(done["dry_run"] == .boolean(false))
    #expect(done["removed"] == preview["removed"])
    guard
      case let .array(removed)? = done["removed"],
      case let .integer(bytes)? = removed.first?["bytes"]
    else {
      Issue.record("no removed run")
      return
    }

    #expect(removed.first?["run_id"] == .string(recorded.older))
    #expect(bytes > 0)
    #expect(done["bytes"] == .integer(bytes))
    let schema = try PublishedSchema(path: "schemas/output/cli-prune.schema.json")

    #expect(try schema.failures(of: done) == [])
  }

  @Test
  func `a store that cannot be read is a storage error, and nothing is removed`() async throws {
    let recorded = try await recordTwice()
    try workspace.folder.write(".use-cases/runs/stray.txt", "left by a file browser\n")

    let result = await workspace.run(["prune", "--json"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("storage"))
    #expect(try runs().contains(recorded.older))
  }

  @Test
  func `an INVALID workspace is refused as status refuses it, and nothing is removed`(
  ) async throws {
    let recorded = try await recordTwice()
    try workspace.folder.write("use-cases/broken.yml", "use_cases: [\n")

    let status = await workspace.run(["status", "--json"])
    let result = await workspace.run(["prune", "--json"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(try result.document()["error"]?["kind"] == status.document()["error"]?["kind"])
    #expect(try runs() == [recorded.older, recorded.newer])
  }
}
