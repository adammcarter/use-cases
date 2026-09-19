import Foundation
import Testing

/// A `use-cases` process that is already running, and its result once it ends.
///
/// The wait is a suspension on the process's own termination callback, not a
/// blocked thread and not a poll. The callback yields into a stream, which
/// buffers, so a process that ends before anyone waits for it is not lost.
struct UseCasesProcess {
  /// One finished run: its exit code and the bytes it wrote.
  struct Outcome: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
  }

  let terminations: AsyncStream<Int32>
  let outputPath: String
  let errorPath: String

  func outcome() async throws -> Outcome {
    var terminated = terminations.makeAsyncIterator()
    let exitCode = await terminated.next()
    return try Outcome(
      exitCode: #require(exitCode, "the process never reported its exit"),
      standardOutput: #require(text(atPath: outputPath)),
      standardError: #require(text(atPath: errorPath)),
    )
  }

  private func text(atPath path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}
