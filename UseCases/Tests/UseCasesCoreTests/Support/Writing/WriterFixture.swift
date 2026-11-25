import Foundation
import Testing
@testable import UseCasesCore

/// A real workspace folder with a real run writer over it, a clock and a random source the test
/// fixes, and the real reader to read back what was written.
struct WriterFixture {
  let directory: TemporaryDirectory
  let writer: RunWriter

  var workspace: URL {
    directory.url
  }

  init(
    clock: FixedTimekeeper = FixedTimekeeper(),
    random: FixedRandomBits = FixedRandomBits(),
  ) throws {
    directory = try TemporaryDirectory()
    writer = try RunWriter(
      clock: clock,
      random: random,
    )
  }

  /// A verdict as `record` would store it.
  static func result(
    _ status: Verdict = .pass,
    useCase: String = StoreSamples.useCase,
    route: String = StoreSamples.route,
    message: String? = "checked by hand",
  ) -> StoredResult {
    StoredResult(
      useCase: .sample(useCase),
      route: .sample(route),
      fingerprint: .sample("a"),
      verdict: status,
      detail: StoredResultDetail(
        recordedAt: StoreSamples.timestamp,
        origin: .recorded,
        message: message,
        attachments: [],
      ),
    )
  }

  /// Opens a record run, appends the results and seals it.
  @discardableResult
  func recordRun(_ results: [StoredResult] = [Self.result()]) throws -> OpenRun {
    let run = try writer.openRun(
      kind: .record,
      in: workspace,
    )

    for result in results {
      try writer.append(
        result,
        to: run,
      )
    }

    _ = try writer.seal(
      run,
      termination: .completed,
    )

    return run
  }

  func readHistory() throws -> StoreHistory {
    try StoreReader().readHistory(in: workspace)
  }

  func read(_ path: String) throws -> String {
    try String(
      contentsOf: directory.location(of: path),
      encoding: .utf8,
    )
  }

  /// The names in a folder below the workspace, sorted; empty when there is no such folder.
  func names(in path: String) -> [String] {
    let found = (try? FileManager.default
      .contentsOfDirectory(atPath: directory.location(of: path).path)) ?? []

    return found.sorted()
  }
}
