/// A value a handler needed, or the refusal envelope that replaces it.
///
/// The same shape as ``ContextResolution``, for the many small steps that
/// either produce something or end the command: a file read, an argument
/// checked, a key decoded. The TypeScript returns `{ kind: "error", envelope,
/// exitCode }` from each of these, and does not throw.
enum CommandStep<Value> {
  case value(Value)
  case refused(CommandOutput)
}
