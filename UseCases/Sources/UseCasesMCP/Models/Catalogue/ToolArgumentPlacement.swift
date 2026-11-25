/// Where an argument's value goes on the command line (chapter 16 §2).
enum ToolArgumentPlacement: Equatable, Sendable {
  /// `--workspace VALUE`.
  case workspace

  /// `--name VALUE`.
  case option(String)

  /// `--name a,b,c`: a list is one comma-joined value.
  case commaSeparated(String)

  /// `--name a --name b`: a list repeats the option.
  case repeated(String)

  /// `--name`, when the value is true.
  case flag(String)

  /// After `--`, so that a value starting with `-` is never read as a flag.
  case positional

  /// Each element after `--`, in order.
  case positionalList

  /// `--value` when the value is one of `known`; otherwise the value goes after `--`, where the
  /// command line refuses it in its own words. A value is never made into a flag it was not
  /// written as.
  case flagOrPositional(known: [String])

  /// The value is JSON on the command's standard input; ``ToolInput`` says how.
  case standardInput
}
