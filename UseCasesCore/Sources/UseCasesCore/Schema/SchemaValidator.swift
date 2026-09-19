/// The JSON-schema evaluator the 27 published schemas are run through
/// (ADR 0007 decision 7: "a small JSON-schema validator of our own").
///
/// It is a port of AJV's behaviour in the configuration the TypeScript uses
/// (`allErrors`, `strict`), keyword for keyword: the messages it produces, and
/// the ORDER it produces them in, are what the tool being replaced produces.
/// Keywords are evaluated in AJV's own rule order — the untyped group first
/// ($ref, const, enum, not, anyOf, oneOf, allOf, if), then the number, string,
/// array and object groups, each entered only when the DATA is of that type.
struct SchemaValidator {
  /// Every keyword this validator implements. A published schema that uses
  /// anything else fails to compile rather than being silently under-validated.
  static let supportedKeywords: Set<String> = [
    "$schema", "$id", "$defs", "$comment", "$ref",
    "title", "description", "examples", "default",
    "type", "const", "enum",
    "not", "anyOf", "oneOf", "allOf", "if", "then", "else",
    "minimum", "exclusiveMinimum",
    "minLength", "pattern",
    "minItems", "uniqueItems", "items",
    "minProperties", "required", "propertyNames", "additionalProperties", "properties",
    "dependentRequired",
  ]

  let registry: SchemaRegistry

  /// Every rule `value` breaks under `schema`, in evaluation order.
  func violations(
    for value: JSONValue,
    against schema: JSONValue,
  ) -> [SchemaViolation] {
    evaluate(value, schema: schema, in: SchemaScope(root: schema))
  }

  func evaluate(
    _ value: JSONValue,
    schema: JSONValue,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    switch schema {
    case let .bool(alwaysValid):
      alwaysValid ? [] : [scope.violation("false schema", "boolean schema is false")]
    case let .object(keywords):
      evaluate(value, keywords: keywords, in: scope)
    default:
      []
    }
  }

  private func evaluate(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    var found: [SchemaViolation] = []

    if let declaredType = keywords["type"], !matches(value, type: declaredType) {
      found.append(scope.violation("type", "must be \(typeText(declaredType))"))
    }

    found += untypedViolations(value, keywords: keywords, in: scope)

    switch value {
    case let .number(number):
      found += numberViolations(number, keywords: keywords, in: scope)
    case let .string(text):
      found += stringViolations(text, keywords: keywords, in: scope)
    case let .array(items):
      found += arrayViolations(items, keywords: keywords, in: scope)
    case let .object(object):
      found += objectViolations(object, keywords: keywords, in: scope)
    default:
      break
    }

    return found
  }

  // MARK: - References

  func referenceViolations(
    _ value: JSONValue,
    reference: String,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let resolved = resolve(reference: reference, root: scope.root) else {
      return []
    }
    return evaluate(value, schema: resolved.schema, in: scope.rooted(at: resolved.root))
  }

  /// Resolve `$ref` against the document it was written in: a bare fragment
  /// points inside that document, anything else names a sibling schema file.
  func resolve(
    reference: String,
    root: JSONValue,
  ) -> (schema: JSONValue, root: JSONValue)? {
    let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let documentPart = String(parts.first ?? "")
    let pointer = parts.count > 1 ? String(parts[1]) : ""

    let targetRoot: JSONValue
    if documentPart.isEmpty {
      targetRoot = root
    } else {
      let baseIdentifier = root["$id"]?.stringValue ?? ""
      guard let identifier = SchemaRegistry.resolve(
        reference: documentPart,
        against: baseIdentifier,
      ), let schema = registry.schema(withIdentifier: identifier) else {
        return nil
      }
      targetRoot = schema
    }

    guard let schema = JSONPointer.resolve(pointer, in: targetRoot) else {
      return nil
    }
    return (schema, targetRoot)
  }

  // MARK: - Types

  private func matches(
    _ value: JSONValue,
    type: JSONValue,
  ) -> Bool {
    switch type {
    case let .string(name):
      matches(value, typeName: name)
    case let .array(names):
      names.contains { name in
        guard let text = name.stringValue else {
          return false
        }
        return matches(value, typeName: text)
      }
    default:
      true
    }
  }

  private func matches(
    _ value: JSONValue,
    typeName: String,
  ) -> Bool {
    switch typeName {
    case "integer":
      if case let .number(number) = value {
        number.isFinite && number.rounded() == number
      } else {
        false
      }
    case "number":
      value.numberValue != nil
    default:
      value.typeName == typeName
    }
  }

  private func typeText(_ type: JSONValue) -> String {
    switch type {
    case let .string(name):
      name
    case let .array(names):
      names
        .map(\.javaScriptText)
        .joined(separator: ",")
    default:
      type.javaScriptText
    }
  }
}
