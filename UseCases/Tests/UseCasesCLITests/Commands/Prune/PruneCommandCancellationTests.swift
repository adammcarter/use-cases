import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// A prune stopped before it claims its removal removes nothing and says it was cancelled.
struct PruneCommandCancellationTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  @Test
  func `a prune cancelled before it removes anything removes nothing`() async throws {
    await workspace.record("shop.pay.card", "fail")
    await workspace.record("shop.pay.card", "pass")
    let runs = workspace.folder.url.appendingPathComponent(".use-cases/runs")
    let before = try FileManager.default.contentsOfDirectory(atPath: runs.path).sorted()

    let cancel = CancellationSwitch()
    let scope = ObservedCancellationScope(
      makeObserver: {
        cancel
      },
    )
    await scope.begin()
    cancel.raise()

    let command = try PruneCommand.parse(["--json"])
    let result = await command.result(
      session: PruneSession(
        loader: LinkedWorkspaceLoader(
          loader: WorkspaceLoader(),
          transformers: TransformerLinkResolver(),
          resolver: LinkResolver(),
        ),
        pruner: StorePruner(),
        cancellation: scope,
      ),
      workingDirectory: workspace.folder.url,
    )
    await scope.end()

    #expect(result.exitCode == 130)
    #expect(try result.document()["error"]?["kind"] == .string("cancelled"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: runs.path).sorted() == before)
    #expect(before.count == 2)
  }
}
