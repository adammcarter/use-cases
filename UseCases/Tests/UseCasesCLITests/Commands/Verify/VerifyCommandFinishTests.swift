import Foundation
import Testing
@testable import UseCasesCLI

struct VerifyCommandFinishTests {
  private static let schemaPath = "schemas/output/cli-verify.schema.json"

  private let workspace: VerifyWorkspace

  init() throws {
    workspace = try VerifyWorkspace()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  /// Starts a run and has the tests write their report.
  private func startedWithReport() async throws -> JSONValue {
    let started = try await workspace.start()

    try workspace.writeReport(of: started)

    return started
  }

  @Test
  func `a finished run is told as the sealed run, and follows the published schema`() async throws {
    let started = try await startedWithReport()

    let result = await workspace.run(["--json", "verify", "--finish"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try failures(of: document) == [])
    #expect(document["step"] == .string("finish"))
    #expect(document["run_id"] == started["run_id"])
    #expect(document["kind"] == .string("verify"))
    #expect(document["errors"] == .array([]))
    guard case let .array(sources)? = document["sources"] else {
      Issue.record("no sources")
      return
    }

    #expect(sources.count == 1)
    #expect(sources.first?["id"] == .string("unit-tests"))
  }

  @Test
  func `the verdict is the one the transformer's result gave`() async throws {
    _ = try await startedWithReport()

    let document = try await workspace.run(["--json", "verify", "--finish"]).document()

    guard case let .array(results)? = document["results"], let result = results.first else {
      Issue.record("no results")
      return
    }

    #expect(results.count == 1)
    #expect(result["use_case"] == .string("shop.pay.card"))
    #expect(result["route"] == .string("unit-tests"))
    #expect(result["status"] == .string("pass"))
    #expect(result["via"] == .array([.string("unit-tests")]))
  }

  @Test
  func `the verdict counts for status once the run is sealed`() async throws {
    _ = try await startedWithReport()
    _ = await workspace.run(["verify", "--finish"])

    let document = try await workspace.run(["--json", "status"]).document()

    guard case let .array(useCases)? = document["use_cases"] else {
      Issue.record("no use cases")
      return
    }

    #expect(useCases.count == 1)
    #expect(useCases.first?["status"] == .string("verified"))
  }

  @Test
  func `a finish in words gives the counts and the hint to ask the gate`() async throws {
    let started = try await startedWithReport()
    guard case let .string(run)? = started["run_id"] else {
      Issue.record("no run_id")
      return
    }

    let result = await workspace.run(["verify", "--finish"])
    let output = result.standardOutput.split(separator: "\n").map(String.init)

    #expect(result.exitCode == 0)
    #expect(output.first == "run \(run.prefix(8)) · 1 verdict (1 pass) · 0 run errors")
    #expect(output.last == "→ use-cases status --gate")
  }

  @Test
  func `a run sealed with run errors exits 1, and is still told`() async throws {
    _ = try await workspace.start()

    let result = await workspace.run(["--json", "verify", "--finish"])
    let document = try result.document()

    #expect(result.exitCode == 1)
    #expect(try failures(of: document) == [])
    guard case let .array(errors)? = document["errors"], case let .string(error)? = errors.first
    else {
      Issue.record("no errors")
      return
    }

    #expect(error.hasPrefix("unit-tests: no report: nothing was written to reports/unit-tests"))
    #expect(document["results"] == .array([]))
  }

  @Test
  func `a run error in words is listed under the counts`() async throws {
    _ = try await workspace.start()

    let result = await workspace.run(["verify", "--finish"])

    #expect(result.exitCode == 1)
    #expect(result.standardOutput.contains("· 0 verdicts · 1 run error"))
    #expect(result.standardOutput.contains("  ! unit-tests: no report"))
  }

  @Test
  func `without a started run a finish is refused, as refused`() async throws {
    let result = await workspace.run(["--json", "verify", "--finish"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(result.standardError.contains("no started run"))
  }

  @Test
  func `several started runs must be named`() async throws {
    _ = try await workspace.start()
    let second = try await workspace.start()

    let refused = await workspace.run(["--json", "verify", "--finish"])

    #expect(refused.exitCode == 2)
    #expect(refused.standardError.contains("name one with --run-id"))

    guard case let .string(run)? = second["run_id"] else {
      Issue.record("no run_id")
      return
    }
    try workspace.writeReport(of: second)

    let named = await workspace.run(["--json", "verify", "--finish", "--run-id", run])

    #expect(named.exitCode == 0)
    #expect(try named.document()["run_id"] == .string(run))
  }

  @Test
  func `changed settings refuse the finish, as refused, and leave the run open`() async throws {
    _ = try await workspace.start()
    try workspace.folder.write(
      "use-cases-bridge.yml",
      VerifyWorkspace.bridge.replacingOccurrences(of: "unit.xml", with: "other.xml"),
    )

    let result = await workspace.run(["--json", "verify", "--finish"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(result.standardError.contains("changed for this run's validations since `--start`"))
  }

  @Test
  func `with no bridge settings a finish reads nothing and writes nothing`() async throws {
    let bare = try VerifyWorkspace(bridge: nil)

    let result = await bare.run(["--json", "verify", "--finish"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(try failures(of: document) == [])
    #expect(document["results"] == .array([]))
    #expect(document["run_id"] == nil)
    #expect(bare.runs().isEmpty)
    guard case let .array(notes)? = document["notes"], case let .string(note)? = notes.first else {
      Issue.record("no notes")
      return
    }

    #expect(note.contains("use-cases record"))
  }

  @Test
  func `code edited after the start gives no verdict and does not make the exit 1`() async throws {
    _ = try await startedWithReport()
    try workspace.folder.write(
      "tests/pay.swift",
      "// @use-case:shop.pay.card#unit-tests.works\ncheck(changed)\n"
        + "// @use-case:end shop.pay.card#unit-tests.works\n",
    )

    let result = await workspace.run(["--json", "verify", "--finish"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(document["results"] == .array([]))
    guard case let .array(diagnostics)? = document["diagnostics"] else {
      Issue.record("no diagnostics")
      return
    }

    #expect(
      diagnostics.contains { diagnostic in
        diagnostic["problem"] == .string("code changed during the run")
      },
    )
  }
}
