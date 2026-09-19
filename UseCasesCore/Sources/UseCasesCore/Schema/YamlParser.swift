import Foundation
import Yams

/// Reads YAML into JSON under the YAML 1.2 core schema.
///
/// Two constructs are refused before the parser ever sees the document: merge
/// keys, which let one document silently rewrite another, and custom tags, which
/// ask the reader to construct arbitrary types. Scalars then resolve by the core
/// schema — `yes` is a string, `017` is seventeen — and NOT by YAML 1.1 rules,
/// which is what the underlying library would otherwise apply.
public enum YamlParser {
  // MARK: - Patterns

  //
  // Every pattern this parser tests is fixed at compile time, never built
  // from runtime data. `resolve(_:)` below checks a plain scalar against
  // most of these in sequence before falling through to a plain string, so
  // for a matrix of any size this is the majority of the work `scan` and
  // `validate-ledger` do — every id, title, intent and outcome string in
  // every row runs this gauntlet once. `RegularExpression` precompiles the
  // whole list once, alongside the schemas' own `pattern` keyword values,
  // rather than recompiling a pattern on every scalar it is tested against.
  private static let mergeKeyPattern = "(?m)^[ \\t]*<<[ \\t]*:"
  private static let customTagPattern = "(^|[\\s,\\[{])![A-Za-z]"
  private static let nullPattern = "^(?:~|[Nn]ull|NULL)?$"
  private static let boolPattern = "^(?:[Tt]rue|TRUE|[Ff]alse|FALSE)$"
  private static let octalPattern = "^0o[0-7]+$"
  private static let intPattern = "^[-+]?[0-9]+$"
  private static let hexPattern = "^0x[0-9a-fA-F]+$"
  private static let specialFloatPattern = "^(?:[-+]?\\.(?:inf|Inf|INF)|\\.nan|\\.NaN|\\.NAN)$"
  private static let exponentFloatPattern =
    "^[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)[eE][-+]?[0-9]+$"
  private static let decimalFloatPattern = "^[-+]?(?:\\.[0-9]+|[0-9]+\\.[0-9]*)$"

  /// Every pattern above, in one place `RegularExpression` reads to warm its
  /// cache — the single source for each string, so the cache can never drift
  /// from what a call site actually tests.
  static let allPatterns: [String] = [
    mergeKeyPattern,
    customTagPattern,
    nullPattern,
    boolPattern,
    octalPattern,
    intPattern,
    hexPattern,
    specialFloatPattern,
    exponentFloatPattern,
    decimalFloatPattern,
  ]

  /// Parse `source`, refusing merge keys and custom tags outright.
  public static func parseToJSON(
    source: String,
    sourcePath: String,
  ) -> ParsedYamlResult {
    if RegularExpression.matches(source, mergeKeyPattern) {
      return refusal("yaml.merge_key_rejected", "YAML merge keys are not supported.", sourcePath)
    }
    if RegularExpression.matches(source, customTagPattern) {
      return refusal("yaml.custom_tag_rejected", "Custom YAML tags are not supported.", sourcePath)
    }

    let node: Node?
    do {
      node = try Yams.compose(yaml: source, .basic)
    } catch {
      // The library refuses duplicate keys itself; that failure keeps its own
      // frozen code and message rather than becoming a generic parse error.
      if case YamlError.duplicatedKeysInMapping = error {
        return refusal("yaml.duplicate_key", "Map keys must be unique", sourcePath)
      }
      return ParsedYamlResult(
        isValid: false,
        value: nil,
        diagnostics: [
          Diagnostic(code: "parse_error", message: message(for: error), sourcePath: sourcePath),
        ],
      )
    }

    guard let node else {
      return ParsedYamlResult(isValid: true, value: .null, diagnostics: [])
    }

    do {
      return try ParsedYamlResult(isValid: true, value: convert(node), diagnostics: [])
    } catch {
      return ParsedYamlResult(
        isValid: false,
        value: nil,
        diagnostics: [
          Diagnostic(
            code: error.code,
            message: error.message,
            sourcePath: sourcePath,
          ),
        ],
      )
    }
  }

  private static func refusal(
    _ code: String,
    _ message: String,
    _ sourcePath: String,
  ) -> ParsedYamlResult {
    ParsedYamlResult(
      isValid: false,
      value: nil,
      diagnostics: [Diagnostic(code: code, message: message, sourcePath: sourcePath)],
    )
  }

  /// The parse failure text. The wording comes from the YAML library, so it does
  /// NOT match the TypeScript's wording — only the `parse_error` code is
  /// contract.
  private static func message(for error: any Error) -> String {
    if let yamlError = error as? YamlError {
      let firstLine = String(describing: yamlError).components(separatedBy: "\n").first
      guard let firstLine else {
        return "YAML could not be parsed."
      }
      return firstLine.trimmingCharacters(in: .whitespaces)
    }
    return error.localizedDescription
  }

  // MARK: - Conversion

  private static func convert(_ node: Node) throws(YamlConversionError) -> JSONValue {
    switch node {
    case let .scalar(scalar):
      return resolve(scalar)
    case let .sequence(sequence):
      var values: [JSONValue] = []
      for item in sequence {
        try values.append(convert(item))
      }
      return .array(values)
    case let .mapping(mapping):
      var object = JSONObject()
      for (key, value) in mapping {
        let name = try keyText(key)
        guard !object.contains(name) else {
          throw .duplicateKey
        }
        object[name] = try convert(value)
      }
      return .object(object)
    case .alias:
      throw .unresolvedAlias
    }
  }

  private static func keyText(_ node: Node) throws(YamlConversionError) -> String {
    guard case let .scalar(scalar) = node else {
      throw .unsupportedKey
    }
    // A JavaScript object key is always a string: `1:` becomes "1".
    return switch resolve(scalar) {
    case .null: "null"
    case let .bool(flag): flag ? "true" : "false"
    case let .number(number): JavaScriptNumber.text(number)
    default: scalar.string
    }
  }

  /// The YAML 1.2 core schema, tag by tag, in the order the `yaml` package
  /// applies them. Only a PLAIN scalar is resolved; anything quoted is a string.
  private static func resolve(_ scalar: Node.Scalar) -> JSONValue {
    guard scalar.style == .plain || scalar.style == .any else {
      return .string(scalar.string)
    }
    let text = scalar.string
    if RegularExpression.matches(text, nullPattern) {
      return .null
    }
    if RegularExpression.matches(text, boolPattern) {
      return .bool(text.lowercased().hasPrefix("t"))
    }
    if RegularExpression.matches(text, octalPattern),
       let value = UInt64(text.dropFirst(2), radix: 8)
    {
      return .number(Double(value))
    }
    if RegularExpression.matches(text, intPattern), let value = Double(text) {
      return .number(value)
    }
    if RegularExpression.matches(text, hexPattern),
       let value = UInt64(text.dropFirst(2), radix: 16)
    {
      return .number(Double(value))
    }
    if RegularExpression.matches(text, specialFloatPattern) {
      if text.lowercased().hasSuffix("nan") {
        return .number(.nan)
      }
      return .number(text.hasPrefix("-") ? -.infinity : .infinity)
    }
    if RegularExpression.matches(text, exponentFloatPattern), let value = Double(text) {
      return .number(value)
    }
    if RegularExpression.matches(text, decimalFloatPattern),
       let value = Double(text)
    {
      return .number(value)
    }
    return .string(text)
  }
}

/// What can go wrong turning a parsed YAML tree into JSON.
enum YamlConversionError: Error {
  case duplicateKey
  case unsupportedKey
  case unresolvedAlias

  var code: String {
    switch self {
    case .duplicateKey: "yaml.duplicate_key"
    case .unsupportedKey, .unresolvedAlias: "parse_error"
    }
  }

  var message: String {
    switch self {
    case .duplicateKey: "Map keys must be unique"
    case .unsupportedKey: "Only scalar mapping keys are supported."
    case .unresolvedAlias: "Unresolved YAML alias."
    }
  }
}
