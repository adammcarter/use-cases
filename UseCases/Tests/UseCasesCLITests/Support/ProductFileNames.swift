import Foundation
import UseCasesCore
@testable import UseCasesCLI

/// The names of the files the tool itself reads and writes: what a real `init` creates, the
/// files of the results store (chapter 12) and the `AGENTS.md` that chapter 21 has the decision
/// recorded in.
enum ProductFileNames {
  private static let storeFiles = [
    "run-order.json", "run.json", "start.json", "results.jsonl", "completion.json",
  ]

  /// The base names. `init` is run for real in a folder of its own, so a file it stops creating,
  /// or a new one it creates, is followed.
  static func current() async throws -> Set<String> {
    let folder = try TemporaryFolder()
    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: ["init", "--no-input"])

    guard result.exitCode == 0 else {
      throw InitFailure(message: result.standardError)
    }

    let created = FileManager.default.enumerator(atPath: folder.url.path)?
      .compactMap { $0 as? String }
      .filter { path in
        !path.hasPrefix(".git") && URL(fileURLWithPath: path).pathExtension != ""
      }
      .map { path in
        URL(fileURLWithPath: path).lastPathComponent
      } ?? []

    return Set(created + storeFiles + ["AGENTS.md"])
  }

  struct InitFailure: Error {
    let message: String
  }
}
