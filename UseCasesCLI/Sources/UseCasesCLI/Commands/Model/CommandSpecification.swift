/// Runs a matched command. It returns the output rather than writing it, so
/// rendering stays in one place.
typealias CommandHandler = @Sendable (HandlerContext) async throws(CommandFailure) -> CommandOutput

/// One leaf command as data: its token path, envelope id, help and flags, and
/// the handler that runs it.
struct CommandSpecification: Sendable {
  /// The tokens that select it, e.g. `["matrix", "validate"]`.
  let path: [String]

  /// The envelope's `command`, e.g. `matrix.validate`.
  let command: String

  let summary: String
  let flags: [FlagSpecification]

  /// Left out of generated help, still dispatchable.
  let isHidden: Bool

  /// False while the command's port is owned by a later ladder subrow.
  let isPorted: Bool

  let handler: CommandHandler

  /// A command the Swift CLI runs.
  init(
    path: [String],
    command: String,
    summary: String,
    flags: [FlagSpecification],
    isHidden: Bool = false,
    handler: @escaping CommandHandler,
  ) {
    self.path = path
    self.command = command
    self.summary = summary
    self.flags = flags
    self.isHidden = isHidden
    isPorted = true
    self.handler = handler
  }

  /// A command declared for help and flag checking whose port has not landed:
  /// it refuses honestly when run.
  init(
    unportedPath path: [String],
    command: String,
    summary: String,
    flags: [FlagSpecification],
    subrow: String,
  ) {
    self.path = path
    self.command = command
    self.summary = summary
    self.flags = flags
    isHidden = false
    isPorted = false
    handler = { _ throws(CommandFailure) in
      NotYetPorted.output(
        command: command,
        invocation: path.joined(separator: " "),
        subrow: subrow,
      )
    }
  }
}
