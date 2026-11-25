import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// A prune while a verify run is being written: the run is started and held at its test command,
/// prune runs, and only then is the run let go. The run survives and seals; prune removes only the
/// superseded run. The hold is an event, not a time.
struct PruneVerifyRaceTests {
  private let holdFolder: TemporaryFolder
  private let hold: ChildHold
  private let workspace: VerifyWorkspace

  init() throws {
    holdFolder = try TemporaryFolder()
    hold = try ChildHold(at: holdFolder.url.appendingPathComponent("hold.fifo"))
    workspace = try VerifyWorkspace(bridge: VerifyWorkspace.bridge(holdingOn: hold))
  }

  private func runs() throws -> [String] {
    try FileManager.default.contentsOfDirectory(
      atPath: workspace.url.appendingPathComponent(".use-cases/runs").path,
    ).sorted()
  }

  /// Prune runs once the verify run is started and held at its test command, then lets it go.
  private static func pruneOnceHeld(
    _ hold: ChildHold,
    in url: URL,
  ) -> Task<(result: CommandResult, during: [String])?, Never> {
    Task {
      defer {
        hold.release()
      }

      guard await hold.waitUntilHeld() != nil else {
        return nil
      }

      let result = await CommandLineRunner(
        loader: WorkspaceLoader(),
        workingDirectory: url,
      ).run(arguments: ["--json", "prune"])
      let during = (try? FileManager.default.contentsOfDirectory(
        atPath: url.appendingPathComponent(".use-cases/runs").path,
      )) ?? []

      return (result, during.sorted())
    }
  }

  @Test
  func `a run being written survives a prune and seals`() async throws {
    let older = await workspace.run(["--json", "record", "shop.pay.card", "unit-tests", "fail"])
    let newer = await workspace.run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])
    let olderRun = try #require(try older.document()["run_id"])
    let newerRun = try #require(try newer.document()["run_id"])

    let url = workspace.url
    let hold = hold
    defer {
      hold.release()
    }

    let pruning = Self.pruneOnceHeld(
      hold,
      in: url,
    )

    let verified = await workspace.run(["--json", "verify", "--run"])
    let raced = try #require(await pruning.value)
    let pruned = try raced.result.document()
    let during = raced.during
    let sealed = try verified.document()
    let runID = try #require(sealed["run_id"])

    guard case let .array(removed)? = pruned["removed"] else {
      Issue.record("no removed runs")
      return
    }

    #expect(removed.map { run in
      run["run_id"]
    } == [olderRun])
    #expect(pruned["kept"] == .array([]))
    #expect(during.count == 2)
    #expect(during.contains { name in
      .string(name) == newerRun
    })
    guard case let .string(identifier) = runID else {
      Issue.record("no run id")
      return
    }

    #expect(FileManager.default.fileExists(
      atPath: workspace.url.appendingPathComponent(".use-cases/runs/\(identifier)/completion.json")
        .path,
    ))
    #expect(try runs() == [newerRun, runID].compactMap { value in
      if case let .string(text) = value {
        text
      } else {
        nil
      }
    }.sorted())
  }
}
