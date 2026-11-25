/// A run folder with no `completion.json`: started and waiting to be finished, or interrupted
/// (chapter 12 §6). It is listed and never counts as evidence.
struct UnfinishedRun: Equatable, Sendable, CustomStringConvertible {
  let identifier: RunIdentifier

  /// `run <id> never finished`
  var description: String {
    "run \(identifier) never finished"
  }
}
