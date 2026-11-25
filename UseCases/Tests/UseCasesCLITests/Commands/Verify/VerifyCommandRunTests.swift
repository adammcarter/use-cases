import Foundation
import Testing
@testable import UseCasesCLI

struct VerifyCommandRunTests {
  private static let schemaPath = "schemas/output/cli-verify.schema.json"

  private let workspace: VerifyWorkspace

  init() throws {
    workspace = try VerifyWorkspace(
      bridge: VerifyWorkspace.bridge(running: "echo report > \"$1\""),
    )
  }

  @Test
  func `a run is told as the sealed run, with the command it ran, and follows the schema`()
    async throws
  {
    let result = await workspace.run(["--json", "verify", "--run"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: document) == [])
    #expect(document["step"] == .string("run"))
    #expect(document["kind"] == .string("verify"))
    #expect(document["errors"] == .array([]))
    guard case let .array(sources)? = document["sources"], let source = sources.first else {
      Issue.record("no sources")
      return
    }

    #expect(source["id"] == .string("unit-tests"))
    #expect(source["exit_code"] == .integer(0))
    #expect(source["command"] != nil)
    #expect(source["seconds"] != nil)
  }

  @Test
  func `the verdict counts for status once the run is sealed`() async throws {
    _ = await workspace.run(["verify", "--run"])

    let document = try await workspace.run(["--json", "status"]).document()

    guard case let .array(useCases)? = document["use_cases"] else {
      Issue.record("no use cases")
      return
    }

    #expect(useCases.first?["status"] == .string("verified"))
  }

  @Test
  func `a run in words gives the counts and the hint to ask the gate`() async {
    let result = await workspace.run(["verify", "--run"])
    let lines = result.standardOutput.split(separator: "\n").map(String.init)

    #expect(result.exitCode == 0)
    #expect(lines.first?.hasSuffix("1 verdict (1 pass) · 0 run errors") == true)
    #expect(lines.last == "→ use-cases status --gate")
  }

  @Test
  func `quiet leaves out the hint`() async {
    let result = await workspace.run(["verify", "--run", "--quiet"])

    #expect(result.standardOutput.split(separator: "\n").count == 1)
  }

  @Test
  func `the console of the command is kept in the run`() async throws {
    let document = try await workspace.run(["--json", "verify", "--run"]).document()

    guard case let .string(run)? = document["run_id"] else {
      Issue.record("no run_id")
      return
    }

    let console = try workspace.read(".use-cases/runs/\(run)/outputs/unit-tests/console.txt")

    #expect(console.isEmpty)
  }

  @Test
  func `a run sealed with run errors exits 1, and is still told`() async throws {
    let bare = try VerifyWorkspace(bridge: VerifyWorkspace.bridge(running: "true"))

    let result = await bare.run(["--json", "verify", "--run"])
    let document = try result.document()

    #expect(result.exitCode == 1)
    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: document) == [])
    guard case let .array(errors)? = document["errors"], case let .string(error)? = errors.first
    else {
      Issue.record("no errors")
      return
    }

    #expect(error.hasPrefix("unit-tests: no report: nothing was written to reports/unit-tests"))
    #expect(document["results"] == .array([]))
  }

  @Test
  func `only runs the validations it names`() async throws {
    let document = try await workspace.run(
      ["--json", "verify", "--run", "--only", "unit-tests"],
    ).document()

    #expect(document["step"] == .string("run"))
    #expect(document["errors"] == .array([]))
  }

  @Test
  func `an unknown validation in --only is a usage refusal, and nothing is written`() async throws {
    let result = await workspace.run(["--json", "verify", "--run", "--only", "nope"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `with no validation set up it says so, and writes nothing`() async throws {
    let none = try VerifyWorkspace(bridge: nil)

    let result = await none.run(["--json", "verify", "--run"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: document) == [])
    #expect(document["step"] == .string("run"))
    #expect(none.runs().isEmpty)
  }
}
