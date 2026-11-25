import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// What a signal does to each step of `verify` (chapter 13 §15, chapter 16 §5, §6).
struct VerifyCommandCancellationTests {
  private static let schemaPath = "schemas/output/cli-verify.schema.json"

  /// Where the hold lives: outside the workspace, which the product reads.
  private let holdFolder: TemporaryFolder
  private let hold: ChildHold
  private let workspace: VerifyWorkspace

  /// The validation's run command is held until the test lets it go.
  init() throws {
    holdFolder = try TemporaryFolder()
    hold = try ChildHold(at: holdFolder.url.appendingPathComponent("hold.fifo"))
    workspace = try VerifyWorkspace(bridge: VerifyWorkspace.bridge(holdingOn: hold))
  }

  /// Runs `verify --run` and cancels it once its command is running and held: the request is
  /// stopped in the middle of the run.
  private func runCancelledWhileRunning() async -> CommandResult {
    let (hold, cancel) = (hold, CancellationSwitch())
    defer {
      hold.release()
    }

    // Not awaited: should the run end without ever starting its command, this stays suspended,
    // holding no thread, until the test process ends, and the test fails on what it was told.
    _ = Task {
      if await hold.waitUntilHeld() != nil {
        cancel.raise()
      }
    }

    return await workspace.run(
      ["--json", "verify", "--run"],
      cancellation: {
        cancel
      },
    )
  }

  // @use-case:cli.exit-codes#swift-tests.cancelled-is-130
  @Test
  func `a cancelled run is told as the sealed run, with cancelled true, and exits 130`()
    async throws
  {
    let result = await runCancelledWhileRunning()
    let document = try result.document()

    #expect(result.exitCode == 130)
    #expect(result.standardError == "use-cases verify: cancelled\n")
    #expect(try PublishedSchema(path: Self.schemaPath).failures(of: document) == [])
    #expect(document["step"] == .string("run"))
    #expect(document["cancelled"] == .boolean(true))
    #expect(document["results"] == .array([]))
    guard case let .array(notes)? = document["notes"], case let .string(note)? = notes.last else {
      Issue.record("no notes")
      return
    }

    #expect(note.contains("sources not processed: unit-tests"))
  }

  // @use-case:end cli.exit-codes#swift-tests.cancelled-is-130

  @Test
  func `a cancelled run sealed as interrupted is no evidence`() async throws {
    _ = await runCancelledWhileRunning()

    let document = try await workspace.run(["--json", "status"]).document()

    guard case let .array(useCases)? = document["use_cases"] else {
      Issue.record("no use cases")
      return
    }

    #expect(useCases.first?["status"] == .string("unverified"))
    #expect(workspace.runs().count == 1)
  }

  @Test
  func `a run cancelled before it began is the cancelled document, and writes nothing`()
    async throws
  {
    let result = await workspace.run(
      ["--json", "verify", "--run"],
      cancellation: { MockCancellation.always },
    )
    let document = try result.document()

    #expect(result.exitCode == 130)
    #expect(document["error"]?["kind"] == .string("cancelled"))
    #expect(document["command"] == .string("verify"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `a start cancelled before it began opens no run`() async throws {
    let result = await workspace.run(
      ["--json", "verify", "--start"],
      cancellation: { MockCancellation.always },
    )

    #expect(result.exitCode == 130)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(workspace.runs().isEmpty)
  }

  // @use-case:cli.exit-codes#swift-tests.cancelled-is-130
  @Test(arguments: [["validate"], ["links"], ["status"]])
  func `a read-only command that is cancelled prints the cancelled document`(
    arguments: [String],
  ) async throws {
    let result = await workspace.run(
      ["--json"] + arguments,
      cancellation: { MockCancellation.always },
    )
    let document = try result.document()

    #expect(result.exitCode == 130)
    #expect(document["command"] == .string(arguments[0]))
    #expect(document["error"]?["kind"] == .string("cancelled"))
    #expect(result.standardError == "use-cases \(arguments[0]): cancelled\n")
  }

  // @use-case:end cli.exit-codes#swift-tests.cancelled-is-130

  @Test
  func `a record cancelled before it began stores nothing`() async throws {
    let result = await workspace.run(
      ["--json", "record", "shop.pay.card", "unit-tests", "pass"],
      cancellation: { MockCancellation.always },
    )

    #expect(result.exitCode == 130)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `a refusal stays a refusal when a signal came too`() async throws {
    let result = await workspace.run(
      ["--json", "verify", "--finish"],
      cancellation: { MockCancellation.always },
    )

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
  }
}
