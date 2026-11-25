import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct VerifyCommandAbortTests {
  private static let schemaPath = "schemas/output/cli-verify.schema.json"

  private let workspace: VerifyWorkspace

  init() throws {
    workspace = try VerifyWorkspace()
  }

  @Test
  func `the abort document is exactly the run it closed`() async throws {
    let started = try await workspace.start()

    let result = await workspace.run(["--json", "verify", "--abort"])

    #expect(result.exitCode == 0)
    #expect(
      try result.document() == .object([
        "output_version": .integer(1),
        "command": .string("verify"),
        "step": .string("abort"),
        "run_id": #require(started["run_id"]),
        "aborted": .boolean(true),
      ]),
    )
    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: result.document()) == [])
  }

  @Test
  func `an abort in words says the run it closed`() async throws {
    let started = try await workspace.start()
    guard case let .string(run)? = started["run_id"] else {
      Issue.record("no run_id")
      return
    }

    let result = await workspace.run(["verify", "--abort"])

    #expect(result.standardOutput == "aborted run \(run)\n")
  }

  @Test
  func `an aborted run cannot be finished, and nothing else is open`() async throws {
    _ = try await workspace.start()
    _ = await workspace.run(["verify", "--abort"])

    let result = await workspace.run(["verify", "--finish"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no started run"))
  }

  @Test
  func `with nothing open an abort is refused, as refused`() async throws {
    let result = await workspace.run(["--json", "verify", "--abort"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
  }

  @Test
  func `several open runs must be named, and the named one is closed`() async throws {
    let first = try await workspace.start()
    let second = try await workspace.start()

    let refused = await workspace.run(["--json", "verify", "--abort"])

    #expect(refused.exitCode == 2)
    #expect(refused.standardError.contains("name one with --run-id"))

    guard case let .string(run)? = second["run_id"] else {
      Issue.record("no run_id")
      return
    }

    let named = await workspace.run(["--json", "verify", "--abort", "--run-id", run])

    #expect(named.exitCode == 0)
    #expect(try named.document()["run_id"] == .string(run))
    #expect(first["run_id"] != .string(run))
  }

  // MARK: - An abort needs the store, not the model (chapter 13 §6)

  // Mutant: VerifyCommand loads the workspace and its links before the abort branch again. An
  // INVALID use case file or a failing links transformer then refuses the abort.

  @Test
  func `an INVALID use case file does not keep a run open`() async throws {
    let started = try await workspace.start()

    try workspace.folder.write("use-cases/broken.yml", "use_cases: [oops\n")

    #expect(await workspace.run(["verify", "--finish"]).exitCode == 2)

    let result = await workspace.run(["--json", "verify", "--abort"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["run_id"] == started["run_id"])
  }

  @Test
  func `a links transformer that fails does not keep a run open`() async throws {
    let started = try await workspace.start()

    try workspace.folder.writeProgram("tools/links", "exit 1\n")
    try workspace.folder.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nlinks:\n  - transformer: tools/links\nvalidations:\n"
        + "  - id: unit-tests\n    report: unit.xml\n    transformer: tools/results\n",
    )

    #expect(await workspace.run(["status"]).exitCode == 2)

    let result = await workspace.run(["--json", "verify", "--abort"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["run_id"] == started["run_id"])
  }

  @Test
  func `a bridge file that cannot be read does not keep a run open`() async throws {
    _ = try await workspace.start()

    try workspace.folder.write("use-cases-bridge.yml", "schema_version: [\n")

    #expect(await workspace.run(["verify", "--abort"]).exitCode == 0)
  }

  @Test
  func `staged results, whole and torn, are dropped and the run is closed as interrupted`()
    async throws
  {
    let started = try await workspace.start()
    guard case let .string(run)? = started["run_id"] else {
      Issue.record("no run_id")
      return
    }

    let log = workspace.url.appendingPathComponent(".use-cases/runs/\(run)/results.jsonl")
    try Data("{\"use_case\":\"shop.pay.card\",\"rou".utf8).write(to: log)

    let refused = await workspace.run(["--json", "verify", "--finish"])

    #expect(refused.exitCode == 2)
    #expect(refused.standardError.contains("--abort --run-id \(run)"))

    let result = await workspace.run(["--json", "verify", "--abort"])
    let completion = try workspace.read(".use-cases/runs/\(run)/completion.json")

    #expect(result.exitCode == 0)
    #expect(completion.contains("\"termination\": \"interrupted\""))
    #expect(completion.contains("\"result_count\": 0"))
    #expect(try workspace.read(".use-cases/runs/\(run)/results.jsonl").isEmpty)
  }

  @Test
  func `it finds the root from a folder below it`() async throws {
    let started = try await workspace.start()
    try workspace.folder.write("deep/down/file.txt", "x")

    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: workspace.url.appendingPathComponent("deep/down"),
    ).run(arguments: ["--json", "verify", "--abort"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["run_id"] == started["run_id"])
  }

  @Test
  func `with no workspace there is nothing to abort, told as invalid`() async throws {
    let empty = try TemporaryFolder()

    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: empty.url,
    ).run(arguments: ["--json", "verify", "--abort"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
  }

  // MARK: - A run whose own files are damaged (chapter 13 §6)

  @Test
  func `a damaged run is refused by name as a storage error, and closed by its run id`()
    async throws
  {
    let started = try await workspace.start()
    guard case let .string(run)? = started["run_id"] else {
      Issue.record("no run_id")
      return
    }

    try workspace.folder.write(".use-cases/runs/\(run)/start.json", "garbage")

    for step in ["--abort", "--finish"] {
      let refused = await workspace.run(["--json", "verify", step])

      #expect(refused.exitCode == 2)
      #expect(try refused.document()["error"]?["kind"] == .string("storage"))
      #expect(refused.standardError.contains(".use-cases/runs/\(run)/start.json"))
    }

    let closed = await workspace.run(["--json", "verify", "--abort", "--run-id", run])

    #expect(closed.exitCode == 0)
    #expect(try closed.document()["run_id"] == .string(run))
    #expect(await workspace.run(["--json", "verify", "--abort"]).exitCode == 2)
  }
}
