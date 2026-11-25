/// The time limits chapter 10 and chapter 14 set.
enum ProcessTimeout {
  /// A run command with no `timeout_seconds` (chapter 14 §11).
  static let runCommandDefault = Duration.seconds(600)

  /// A transformer has this long to answer (chapter 10 §10).
  static let transformer = Duration.seconds(120)

  /// The limit of a run command: its `timeout_seconds`, else the default.
  static func runCommand(timeoutSeconds: Int?) -> Duration {
    guard let timeoutSeconds else {
      return runCommandDefault
    }

    return .seconds(timeoutSeconds)
  }
}
