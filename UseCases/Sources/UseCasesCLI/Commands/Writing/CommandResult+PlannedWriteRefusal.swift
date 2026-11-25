extension CommandResult {
  /// A plan that was refused, or could not be written (chapter 16 §6).
  static func refusal(
    _ error: PlannedWriteError,
    command: String,
    json: Bool,
  ) -> CommandResult {
    switch error {
    case let .conflicting(error), let .writing(error):
      .refusal(
        .refused,
        message: error.message,
        command: command,
        json: json,
      )
    case let .diverges(message):
      .refusal(
        .refused,
        message: message,
        command: command,
        json: json,
      )
    case let .leavesInvalid(error):
      .refusal(
        error,
        command: command,
        json: json,
      )
    }
  }
}
