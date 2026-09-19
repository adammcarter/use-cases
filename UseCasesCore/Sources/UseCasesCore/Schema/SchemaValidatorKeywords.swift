/// The type-specific keyword groups. Each is entered only when the DATA is of
/// that type, which is why `{"type":"string","minLength":3}` against a number
/// reports the type and nothing else.
extension SchemaValidator {
  func numberViolations(
    _ number: Double,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    var found: [SchemaViolation] = []
    if case let .number(limit)? = keywords["minimum"], number < limit {
      found.append(scope.violation("minimum", "must be >= \(JavaScriptNumber.text(limit))"))
    }
    if case let .number(limit)? = keywords["exclusiveMinimum"], number <= limit {
      found.append(
        scope.violation("exclusiveMinimum", "must be > \(JavaScriptNumber.text(limit))"),
      )
    }
    return found
  }

  func stringViolations(
    _ text: String,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    var found: [SchemaViolation] = []
    // AJV measures a string in code points, not characters or UTF-16 units.
    if case let .number(limit)? = keywords["minLength"],
       Double(text.unicodeScalars.count) < limit
    {
      found.append(
        scope.violation(
          "minLength",
          "must NOT have fewer than \(JavaScriptNumber.text(limit)) characters",
        ),
      )
    }
    if case let .string(pattern)? = keywords["pattern"], !RegularExpression.matches(text, pattern) {
      found.append(scope.violation("pattern", "must match pattern \"\(pattern)\""))
    }
    return found
  }

  func arrayViolations(
    _ items: [JSONValue],
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    var found: [SchemaViolation] = []

    if case let .number(limit)? = keywords["minItems"], Double(items.count) < limit {
      found.append(
        scope.violation(
          "minItems",
          "must NOT have fewer than \(JavaScriptNumber.text(limit)) items",
        ),
      )
    }

    if keywords["uniqueItems"] == .bool(true), let pair = firstDuplicate(in: items) {
      found.append(
        scope.violation(
          "uniqueItems",
          "must NOT have duplicate items (items ## \(pair.earlier) and \(pair.later) "
            + "are identical)",
        ),
      )
    }

    if let itemSchema = keywords["items"] {
      for (index, item) in items.enumerated() {
        found += evaluate(item, schema: itemSchema, in: scope.descending(toIndex: index))
      }
    }

    return found
  }

  /// The object group, in AJV's order: `minProperties`, `required`,
  /// `propertyNames`, `additionalProperties`, `properties`, and — from the 2020
  /// vocabulary, after all of those — `dependentRequired`.
  func objectViolations(
    _ object: JSONObject,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    var found: [SchemaViolation] = []

    if case let .number(limit)? = keywords["minProperties"], Double(object.count) < limit {
      found.append(
        scope.violation(
          "minProperties",
          "must NOT have fewer than \(JavaScriptNumber.text(limit)) properties",
        ),
      )
    }

    found += requiredViolations(object, keywords: keywords, in: scope)
    found += propertyNameViolations(object, keywords: keywords, in: scope)
    found += additionalPropertyViolations(object, keywords: keywords, in: scope)
    found += propertyViolations(object, keywords: keywords, in: scope)
    found += dependencyViolations(object, keywords: keywords, in: scope)
    return found
  }

  private func requiredViolations(
    _ object: JSONObject,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard case let .array(required)? = keywords["required"] else {
      return []
    }
    var found: [SchemaViolation] = []
    for case let .string(property) in required where !object.contains(property) {
      found.append(
        scope.violation(
          "required",
          "must have required property '\(property)'",
          missingProperty: property,
        ),
      )
    }
    return found
  }

  /// A failing key reports the inner violation at the OBJECT's own path — the
  /// key is not a place in the document — and then the `propertyNames` rule.
  private func propertyNameViolations(
    _ object: JSONObject,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let nameSchema = keywords["propertyNames"] else {
      return []
    }
    var found: [SchemaViolation] = []
    for key in object.keys {
      let nameViolations = evaluate(.string(key), schema: nameSchema, in: scope)
      guard !nameViolations.isEmpty else {
        continue
      }
      found += nameViolations
      found.append(scope.violation("propertyNames", "property name must be valid"))
    }
    return found
  }

  /// Extra members are reported in the order the DATA lists them, not the order
  /// the schema declares anything.
  private func additionalPropertyViolations(
    _ object: JSONObject,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let additional = keywords["additionalProperties"] else {
      return []
    }
    let declared = keywords["properties"]?.objectValue
    var found: [SchemaViolation] = []
    for (key, value) in object.pairs where declared?.contains(key) != true {
      if additional == .bool(false) {
        found.append(
          scope.violation("additionalProperties", "must NOT have additional properties"),
        )
      } else {
        found += evaluate(value, schema: additional, in: scope.descending(to: key))
      }
    }
    return found
  }

  /// Members are visited in the order the SCHEMA declares them.
  private func propertyViolations(
    _ object: JSONObject,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let declared = keywords["properties"]?.objectValue else {
      return []
    }
    var found: [SchemaViolation] = []
    for (key, propertySchema) in declared.pairs {
      guard let member = object[key] else {
        continue
      }
      found += evaluate(member, schema: propertySchema, in: scope.descending(to: key))
    }
    return found
  }

  private func dependencyViolations(
    _ object: JSONObject,
    keywords: JSONObject,
    in scope: SchemaScope,
  ) -> [SchemaViolation] {
    guard let dependencies = keywords["dependentRequired"]?.objectValue else {
      return []
    }
    var found: [SchemaViolation] = []
    for (property, requirement) in dependencies.pairs {
      guard object.contains(property), case let .array(dependents) = requirement else {
        continue
      }
      let names = dependents.compactMap(\.stringValue)
      let wording = names.count == 1 ? "property" : "properties"
      for name in names where !object.contains(name) {
        found.append(
          scope.violation(
            "dependentRequired",
            "must have \(wording) \(names.joined(separator: ", ")) when property "
              + "\(property) is present",
            missingProperty: name,
          ),
        )
      }
    }
    return found
  }

  /// AJV scans for duplicates from the END of the array inwards, and names the
  /// first pair it meets. The order it reports is part of the message.
  private func firstDuplicate(in items: [JSONValue]) -> (earlier: Int, later: Int)? {
    var later = items.count - 1
    while later > 0 {
      var earlier = later - 1
      while earlier >= 0 {
        if items[later] == items[earlier] {
          return (earlier, later)
        }
        earlier -= 1
      }
      later -= 1
    }
    return nil
  }
}
