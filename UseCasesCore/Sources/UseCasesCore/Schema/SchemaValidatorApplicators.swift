/// The untyped keyword group, in AJV's registration order: `$ref`, `const`,
/// `enum`, then the applicators `not`, `anyOf`, `oneOf`, `allOf` and `if`.
///
/// This group runs BEFORE the type-specific ones and runs even when the declared
/// `type` did not match, which is why a wrong-typed enum value reports both.
extension SchemaValidator {
  func untypedViolations(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    var found: [SchemaViolation] = []

    if case let .string(reference)? = keywords["$ref"] {
      found += referenceViolations(value, reference: reference, in: scope)
    }
    if let expected = keywords["const"], expected != value {
      found.append(scope.violation("const", "must be equal to constant"))
    }
    if case let .array(allowed)? = keywords["enum"], !allowed.contains(value) {
      found.append(
        scope.violation(
          "enum",
          "must be equal to one of the allowed values",
          allowedValues: allowed,
        ),
      )
    }
    found += notViolations(value, keywords: keywords, in: scope)
    found += anyOfViolations(value, keywords: keywords, in: scope)
    found += oneOfViolations(value, keywords: keywords, in: scope)
    found += allOfViolations(value, keywords: keywords, in: scope)
    found += conditionalViolations(value, keywords: keywords, in: scope)
    return found
  }

  /// `not` swallows the errors of the schema it negates: they describe why the
  /// value did NOT match, which is the outcome being asked for.
  private func notViolations(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let negated = keywords["not"],
          evaluate(value, schema: negated, in: scope).isEmpty
    else {
      return []
    }
    return [scope.violation("not", "must NOT be valid")]
  }

  private func anyOfViolations(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard case let .array(branches)? = keywords["anyOf"] else {
      return []
    }
    let perBranch = violations(value, branches: branches, in: scope)
    guard perBranch.allSatisfy({ !$0.isEmpty }) else {
      return []
    }
    return perBranch.flatMap(\.self) + [scope.violation("anyOf", "must match a schema in anyOf")]
  }

  private func oneOfViolations(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard case let .array(branches)? = keywords["oneOf"] else {
      return []
    }
    let perBranch = violations(value, branches: branches, in: scope)
    guard perBranch.filter(\.isEmpty).count != 1 else {
      return []
    }
    return perBranch.flatMap(\.self)
      + [scope.violation("oneOf", "must match exactly one schema in oneOf")]
  }

  private func allOfViolations(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard case let .array(branches)? = keywords["allOf"] else {
      return []
    }
    return violations(value, branches: branches, in: scope).flatMap(\.self)
  }

  /// `then` runs only when `if` holds, `else` only when it does not; the branch
  /// errors arrive first and the `if` violation closes them off.
  private func conditionalViolations(
    _ value: JSONValue,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let condition = keywords["if"] else {
      return []
    }
    let holds = evaluate(value, schema: condition, in: scope).isEmpty
    let branchName = holds ? "then" : "else"
    guard let branch = keywords[branchName] else {
      return []
    }
    let branchViolations = evaluate(value, schema: branch, in: scope)
    guard !branchViolations.isEmpty else {
      return []
    }
    return branchViolations + [scope.violation("if", "must match \"\(branchName)\" schema")]
  }

  private func violations(
    _ value: JSONValue,
    branches: [JSONValue],
    in scope: SchemaScope,
  ) -> [[SchemaViolation]] {
    branches.map { branch in
      evaluate(value, schema: branch, in: scope)
    }
  }
}
