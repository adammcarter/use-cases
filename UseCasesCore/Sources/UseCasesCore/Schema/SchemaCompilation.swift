/// The compile-time checks AJV's `strict: true` performs before a schema is ever
/// used: every keyword is one the validator implements, and every `$ref` leads
/// somewhere. Without this, a keyword added to a schema tomorrow would be
/// silently ignored and the document would pass for the wrong reason.
extension SchemaValidator {
  /// The first problem found in `schema`, or nil when it compiles.
  func compilationProblem(
    in schema: JSONValue,
    root: JSONValue,
  ) -> String? {
    var visited = Set<String>()
    return problem(in: schema, root: root, path: "#", visited: &visited)
  }

  private func problem(
    in schema: JSONValue,
    root: JSONValue,
    path: String,
    visited: inout Set<String>,
  ) -> String? {
    guard case let .object(keywords) = schema else {
      return nil
    }
    let rootIdentifier = root["$id"]?.stringValue ?? ""
    guard visited.insert("\(rootIdentifier)\(path)").inserted else {
      return nil
    }
    for key in keywords.keys where !Self.supportedKeywords.contains(key) {
      return "unsupported keyword '\(key)' at \(path)"
    }
    return referenceProblem(in: keywords, root: root, path: path, visited: &visited)
      ?? subschemaProblem(in: keywords, root: root, path: path, visited: &visited)
  }

  private func referenceProblem(
    in keywords: JSONObject,
    root: JSONValue,
    path: String,
    visited: inout Set<String>,
  ) -> String? {
    guard case let .string(reference)? = keywords["$ref"] else {
      return nil
    }
    guard let resolved = resolve(reference: reference, root: root) else {
      return "unresolved $ref '\(reference)' at \(path)"
    }
    return problem(
      in: resolved.schema,
      root: resolved.root,
      path: reference,
      visited: &visited,
    )
  }

  private func subschemaProblem(
    in keywords: JSONObject,
    root: JSONValue,
    path: String,
    visited: inout Set<String>,
  ) -> String? {
    for keyword in ["not", "if", "then", "else", "items", "propertyNames", "additionalProperties"] {
      guard let subschema = keywords[keyword] else {
        continue
      }
      if let found = problem(
        in: subschema,
        root: root,
        path: "\(path)/\(keyword)",
        visited: &visited,
      ) {
        return found
      }
    }

    for keyword in ["allOf", "anyOf", "oneOf"] {
      guard case let .array(branches)? = keywords[keyword] else {
        continue
      }
      for (index, branch) in branches.enumerated() {
        if let found = problem(
          in: branch,
          root: root,
          path: "\(path)/\(keyword)/\(index)",
          visited: &visited,
        ) {
          return found
        }
      }
    }

    guard let properties = keywords["properties"]?.objectValue else {
      return nil
    }
    for (name, propertySchema) in properties.pairs {
      if let found = problem(
        in: propertySchema,
        root: root,
        path: "\(path)/properties/\(name)",
        visited: &visited,
      ) {
        return found
      }
    }
    return nil
  }
}
