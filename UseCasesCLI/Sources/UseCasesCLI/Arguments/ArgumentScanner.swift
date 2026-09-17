import UseCasesCore

/// The compatibility parser (packages/cli/src/args/parse.ts), reproducing the
/// TypeScript's exact semantics rather than a stricter parser's:
///
/// - a flag matches only its exact token, so `--flag=value` is not a form;
/// - a single value is the token after the FIRST occurrence, even when that
///   token looks like another flag;
/// - a repeatable value is the non-empty token after each occurrence;
/// - a number is `Number(value)` when finite;
/// - `parseFlags` reads nothing past a `--` separator.
enum ArgumentScanner {
  static func value(
    after flag: String,
    in arguments: [String],
  ) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }

  static func values(
    after flag: String,
    in arguments: [String],
  ) -> [String]? {
    var collected: [String] = []
    for index in arguments.indices where arguments[index] == flag {
      guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
        continue
      }
      collected.append(arguments[index + 1])
    }
    return collected.isEmpty ? nil : collected
  }

  static func number(
    after flag: String,
    in arguments: [String],
  ) -> Double? {
    guard let text = value(after: flag, in: arguments), !text.isEmpty else {
      return nil
    }
    let parsed = JavaScriptNumber.parse(text)
    return parsed.isFinite ? parsed : nil
  }

  static func parseFlags(
    _ arguments: [String],
    specifications: [FlagSpecification],
  ) -> ParsedFlags {
    var scope = arguments
    if let separator = arguments.firstIndex(of: "--") {
      scope = Array(arguments[..<separator])
    }
    var parsed = ParsedFlags()

    for specification in specifications {
      parsed[specification.key] = parsedValue(of: specification, in: scope)
    }
    return parsed
  }

  private static func parsedValue(
    of specification: FlagSpecification,
    in arguments: [String],
  ) -> ParsedFlagValue? {
    switch specification.kind {
    case .boolean:
      .boolean(arguments.contains(specification.name))
    case .integer:
      number(after: specification.name, in: arguments).map(ParsedFlagValue.number)
    case .string where specification.isRepeatable:
      values(after: specification.name, in: arguments).map(ParsedFlagValue.strings)
    case .string:
      value(after: specification.name, in: arguments).map(ParsedFlagValue.string)
    }
  }
}
