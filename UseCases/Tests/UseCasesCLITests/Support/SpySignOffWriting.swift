import Foundation
@testable import UseCasesCLI

/// A writer of sign-offs that writes nothing: it notes what it was asked, on a stream, and
/// answers as told.
struct SpySignOffWriting: SignOffWriting {
  struct Request: Equatable {
    let paths: [String]
    let root: String
    let command: String
    let dryRun: Bool
    let reportsDryRun: Bool
  }

  /// What it is asked, in order, until ``finish()``.
  let requests: AsyncStream<Request>

  private let noting: AsyncStream<Request>.Continuation
  private let reply: CommandResult

  init(answering reply: CommandResult) {
    (requests, noting) = AsyncStream.makeStream(of: Request.self)
    self.reply = reply
  }

  /// Ends the stream of requests, so that it can be read to its end.
  func finish() {
    noting.finish()
  }

  /// Every request so far.
  func asked() async -> [Request] {
    finish()

    var found: [Request] = []

    for await request in requests {
      found.append(request)
    }

    return found
  }

  func answer(
    _ change: PlannedSignOff,
    command: String,
    global _: GlobalOptions,
    dryRun: Bool,
    report: ([String]) -> any WriteReporting,
  ) async -> CommandResult {
    noting.yield(
      Request(
        paths: change.writes.changes.map(\.path),
        root: change.root.lastPathComponent,
        command: command,
        dryRun: dryRun,
        reportsDryRun: report([]).humanText().contains("would"),
      ),
    )

    return reply
  }
}
