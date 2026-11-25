import Foundation
import Testing
@testable import UseCasesCLI

struct VerifyCommandStartTests {
  private static let schemaPath = "schemas/output/cli-verify.schema.json"

  private let workspace: VerifyWorkspace

  init() throws {
    workspace = try VerifyWorkspace()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  private func lines(_ result: CommandResult) -> [String] {
    result.standardOutput.split(separator: "\n").map(String.init)
  }

  @Test
  func `the start document follows the published schema`() async throws {
    let result = await workspace.run(["--json", "verify", "--start"])

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document()) == [])
  }

  @Test
  func `the start document names the run, what it reads and where each report goes`() async throws {
    let document = try await workspace.start()

    guard case let .string(run)? = document["run_id"] else {
      Issue.record("no run_id")
      return
    }

    #expect(document["step"] == .string("start"))
    #expect(document["started"] == .boolean(true))
    #expect(document["selected"] == .array([.string("unit-tests")]))
    guard case let .string(path)? = document["reports"]?["unit-tests"] else {
      Issue.record("no report path")
      return
    }

    // The core names the workspace by its canonical folder, the test by the system's spelling.
    #expect(path.hasPrefix("/"))
    #expect(path.hasSuffix("/.use-cases/runs/\(run)/reports/unit-tests/unit.xml"))
    #expect(
      URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path
        == workspace.url.appendingPathComponent(".use-cases/runs/\(run)/reports/unit-tests")
        .resolvingSymlinksInPath().path,
    )
    #expect(workspace.runs() == [run])
  }

  @Test
  func `a start in words says the run, where to write, and what to do next`() async throws {
    let result = await workspace.run(["verify", "--start"])
    let output = lines(result)
    let run = try #require(workspace.runs().first)

    #expect(result.exitCode == 0)
    #expect(output.first == "started run \(run)")
    #expect(output[1].hasPrefix("  unit-tests   write the report to "))
    #expect(output.last == "→ run your tests, then: use-cases verify --finish --run-id \(run)")
  }

  @Test
  func `quiet leaves out the hint`() async {
    let result = await workspace.run(["verify", "--start", "--quiet"])

    #expect(!result.standardOutput.contains("→"))
  }

  @Test
  func `a second start says what else is open, and closes nothing`() async throws {
    let first = try await workspace.start()
    let second = try await workspace.start()

    guard case let .array(notes)? = second["notes"], case let .string(note)? = notes.last,
          case let .string(firstRun)? = first["run_id"]
    else {
      Issue.record("no notes")
      return
    }

    #expect(note.contains(firstRun))
    #expect(workspace.runs().count == 2)
  }

  @Test
  func `only starts only those validations`() async throws {
    let document = try await workspace.start(["--only", "unit-tests"])

    #expect(document["selected"] == .array([.string("unit-tests")]))
  }

  @Test
  func `with no bridge settings nothing is started and no run is written`() async throws {
    let bare = try VerifyWorkspace(bridge: nil)

    let result = await bare.run(["--json", "verify", "--start"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(document["started"] == .boolean(false))
    #expect(document["run_id"] == nil)
    #expect(document["reports"] == nil)
    #expect(try failures(of: document) == [])
    #expect(bare.runs().isEmpty)
  }

  @Test
  func `an invalid workspace is refused before anything is written`() async throws {
    try workspace.folder.write("use-cases/broken.yml", "use_cases: [oops\n")

    let result = await workspace.run(["--json", "verify", "--start"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(workspace.runs().isEmpty)
  }
}
