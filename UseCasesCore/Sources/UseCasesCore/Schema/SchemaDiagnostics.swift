import Foundation

/// Translates broken rules into the published diagnostic shape.
///
/// A raw violation says which RULE broke; a reader needs to know which FIELD
/// broke, in which row. The field name is already sitting in the JSON pointer,
/// so it is moved into the message where it will be read, and the row id is
/// resolved out of the document being validated.
enum SchemaDiagnostics {
  static func map(
    _ violations: [SchemaViolation],
    sourcePath: String?,
    document: JSONValue,
  ) -> [Diagnostic] {
    violations.map { violation in
      Diagnostic(
        code: code(for: violation),
        message: message(for: violation),
        sourcePath: sourcePath,
        jsonPointer: violation.instancePath.isEmpty ? nil : violation.instancePath,
        entityIdentifier: entityIdentifier(for: violation, in: document),
      )
    }
  }

  /// Only the `required` keyword names a missing property on the wire; the
  /// dependency keywords carry one too, and AJV does NOT put it in the code.
  private static func requiredProperty(of violation: SchemaViolation) -> String? {
    violation.keyword == "required" ? violation.missingProperty : nil
  }

  private static func code(for violation: SchemaViolation) -> String {
    if violation.keyword == "additionalProperties" {
      return "additional_property"
    }
    if violation.keyword == "enum" || violation.keyword == "const" {
      return "enum.invalid_value"
    }
    switch requiredProperty(of: violation) {
    case "schema_version":
      return "schema_version.required"
    case "observable_outcomes":
      return "use_case.observable_outcomes.required"
    case "approval_policy":
      return "approval_policy.required"
    case let missing?:
      return "\(missing).required"
    case nil:
      return "schema.\(violation.keyword)"
    }
  }

  /// Name the offending FIELD in the message. The raw message describes the
  /// rule, not the thing that broke it — a reader with 36 rows across 3 files
  /// would otherwise get a scavenger hunt.
  private static func message(for violation: SchemaViolation) -> String {
    let base = allowedValuesMessage(for: violation)
    // `required` violations already name the property in the raw message.
    guard let field = requiredProperty(of: violation)
      ?? fieldName(in: violation.instancePath)
    else {
      return base
    }
    return "\(field): \(base)"
  }

  private static func allowedValuesMessage(for violation: SchemaViolation) -> String {
    guard violation.keyword == "enum",
          let allowed = violation.allowedValues,
          !allowed.isEmpty
    else {
      return violation.message
    }
    let names = allowed
      .map(\.javaScriptText)
      .joined(separator: ", ")
    return "\(violation.message) (allowed: \(names))"
  }

  /// The last non-numeric segment of a JSON pointer — `/use_cases/3/value_tier`
  /// yields `value_tier`. Array indices are position, not field, so they are
  /// skipped.
  private static func fieldName(in instancePath: String) -> String? {
    let segments = instancePath
      .components(separatedBy: "/")
      .filter { segment in
        !segment.isEmpty
      }
    for segment in segments.reversed() where Int(segment) == nil {
      return JSONPointer.unescape(segment)
    }
    return nil
  }

  /// Resolve the use-case row a diagnostic belongs to, so the reader is told
  /// WHICH row is broken instead of being handed a bare pointer. Best-effort by
  /// design: a document without `/use_cases/<n>/id` simply yields nil.
  private static func entityIdentifier(
    for violation: SchemaViolation,
    in document: JSONValue,
  ) -> String? {
    let path = violation.instancePath
    guard path.hasPrefix("/use_cases/") else {
      return nil
    }
    let remainder = path.dropFirst("/use_cases/".count)
    let indexText = String(remainder.prefix { $0 != "/" })
    guard !indexText.isEmpty,
          indexText.allSatisfy(\.isNumber),
          let index = Int(indexText),
          document.isRecord,
          let rows = document["use_cases"]?.arrayValue,
          rows.indices.contains(index)
    else {
      return nil
    }
    return rows[index]["id"]?.stringValue
  }
}
