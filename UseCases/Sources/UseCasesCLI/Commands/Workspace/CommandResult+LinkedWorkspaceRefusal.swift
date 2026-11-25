extension CommandResult {
  /// What a workspace that could not be read for links does to a request: a refusal when it is
  /// INVALID, and a cancellation (exit 130, chapter 16 §6) when the run was cancelled while a
  /// link transformer ran.
  static func refusal(
    _ error: LinkedWorkspaceError,
    command: String,
    json: Bool,
  ) -> CommandResult {
    guard let kind = error.refusalKind else {
      return .cancelled(
        command: command,
        json: json,
      )
    }

    return .refusal(
      kind,
      message: error.message,
      command: command,
      json: json,
    )
  }
}
