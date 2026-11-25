extension SchemaCompilation {
  private static let annotations: Set<String> = ["$schema", "title", "description", "default"]

  private static let assertions: Set<String> = [
    "type", "$ref", "const", "enum", "format",
    "pattern", "minLength", "maxLength", "minimum", "maximum",
    "properties", "required", "dependentRequired", "additionalProperties", "propertyNames",
    "items", "minItems", "maxItems", "uniqueItems",
    "allOf", "anyOf", "oneOf", "not", "if", "then", "else",
  ]

  mutating func makeNode(
    keywords: Keywords,
    location: [String],
    isRoot: Bool,
  ) throws(SchemaCompilerError) -> SchemaNode {
    try checkKnown(
      keywords,
      location: location,
      isRoot: isRoot,
    )

    var node = SchemaNode()
    try applyGeneral(
      keywords,
      location: location,
      to: &node,
    )
    try applyValueLimits(
      keywords,
      location: location,
      to: &node,
    )
    try applyObjectKeywords(
      keywords,
      location: location,
      to: &node,
    )
    try applyArrayKeywords(
      keywords,
      location: location,
      to: &node,
    )
    try applyCombinators(
      keywords,
      location: location,
      to: &node,
    )

    return node
  }

  private func checkKnown(
    _ keywords: Keywords,
    location: [String],
    isRoot: Bool,
  ) throws(SchemaCompilerError) {
    let known = Self.annotations.union(Self.assertions).union(isRoot ? ["$defs"] : [])
    for keyword in keywords.keys.sorted() where !known.contains(keyword) {
      throw .unknownKeyword(
        keyword,
        location: Self.text(of: location),
      )
    }
  }

  /// `type`, `$ref`, `const`, `enum` and `format`.
  private mutating func applyGeneral(
    _ keywords: Keywords,
    location: [String],
    to node: inout SchemaNode,
  ) throws(SchemaCompilerError) {
    node.types = try types(
      in: keywords,
      location: location,
    )
    if let reference = try string(
      "$ref",
      in: keywords,
      location: location,
    ) {
      node.reference = try resolve(reference: reference)
    }
    if let name = try string(
      "format",
      in: keywords,
      location: location,
    ) {
      guard let format = SchemaFormat(rawValue: name) else {
        throw .unsupportedFormat(
          name,
          location: Self.text(of: location),
        )
      }
      node.format = format
    }
    node.constant = keywords["const"]
    node.enumeration = try array(
      "enum",
      in: keywords,
      location: location,
    )
  }

  /// `pattern`, `minLength`, `maxLength`, `minimum` and `maximum`.
  private func applyValueLimits(
    _ keywords: Keywords,
    location: [String],
    to node: inout SchemaNode,
  ) throws(SchemaCompilerError) {
    if let source = try string(
      "pattern",
      in: keywords,
      location: location,
    ) {
      let pattern = SchemaPattern(source: source)
      if let construct = pattern.unsupportedSyntax {
        throw .unsupportedPattern(
          source,
          construct: construct,
          location: Self.text(of: location),
        )
      }
      guard pattern.makeRegex() != nil else {
        throw .invalidPattern(
          source,
          location: Self.text(of: location),
        )
      }
      node.pattern = source
    }
    node.minLength = try count(
      "minLength",
      in: keywords,
      location: location,
    )
    node.maxLength = try count(
      "maxLength",
      in: keywords,
      location: location,
    )
    node.minimum = try number(
      "minimum",
      in: keywords,
      location: location,
    )
    node.maximum = try number(
      "maximum",
      in: keywords,
      location: location,
    )
  }

  /// `properties`, `required`, `dependentRequired`, `additionalProperties` and `propertyNames`.
  private mutating func applyObjectKeywords(
    _ keywords: Keywords,
    location: [String],
    to node: inout SchemaNode,
  ) throws(SchemaCompilerError) {
    for member in try object(
      "properties",
      in: keywords,
      location: location,
    ) {
      node.properties[ExactText(member.key)] = try compileSubschema(
        member.value,
        location: location + ["properties", member.key],
      )
    }
    node.required = try strings(
      "required",
      in: keywords,
      location: location,
    ) ?? []
    node.dependentRequired = try dependentRequired(
      in: keywords,
      location: location,
    )

    if let value = keywords["additionalProperties"] {
      node.additionalProperties = try additionalProperties(
        value,
        location: location + ["additionalProperties"],
      )
    }
    if let value = keywords["propertyNames"] {
      node.propertyNames = try compileSubschema(
        value,
        location: location + ["propertyNames"],
      )
    }
  }

  private mutating func additionalProperties(
    _ value: AuthoredValue,
    location: [String],
  ) throws(SchemaCompilerError) -> AdditionalProperties? {
    if case let .boolean(isAllowed) = value {
      return isAllowed || ignoresUnknownMembers ? nil : .forbidden
    }

    return try .schema(compileSubschema(
      value,
      location: location,
    ))
  }

  /// `items`, `minItems`, `maxItems` and `uniqueItems`.
  private mutating func applyArrayKeywords(
    _ keywords: Keywords,
    location: [String],
    to node: inout SchemaNode,
  ) throws(SchemaCompilerError) {
    if let value = keywords["items"] {
      node.items = try compileSubschema(
        value,
        location: location + ["items"],
      )
    }
    node.minItems = try count(
      "minItems",
      in: keywords,
      location: location,
    )
    node.maxItems = try count(
      "maxItems",
      in: keywords,
      location: location,
    )
    node.requiresUniqueItems = try flag(
      "uniqueItems",
      in: keywords,
      location: location,
    ) ?? false
  }

  /// `allOf`, `anyOf`, `oneOf`, `not`, and `if` with `then` and `else`.
  private mutating func applyCombinators(
    _ keywords: Keywords,
    location: [String],
    to node: inout SchemaNode,
  ) throws(SchemaCompilerError) {
    node.allOf = try subschemas(
      "allOf",
      in: keywords,
      location: location,
    )
    node.anyOf = try subschemas(
      "anyOf",
      in: keywords,
      location: location,
    )
    node.oneOf = try subschemas(
      "oneOf",
      in: keywords,
      location: location,
    )
    node.not = try subschema(
      "not",
      in: keywords,
      location: location,
    )
    node.condition = try subschema(
      "if",
      in: keywords,
      location: location,
    )
    node.consequence = try subschema(
      "then",
      in: keywords,
      location: location,
    )
    node.alternative = try subschema(
      "else",
      in: keywords,
      location: location,
    )
  }

  private mutating func subschema(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> Int? {
    guard let value = keywords[keyword] else {
      return nil
    }

    return try compileSubschema(
      value,
      location: location + [keyword],
    )
  }

  private mutating func subschemas(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> [Int] {
    guard let schemas = try array(
      keyword,
      in: keywords,
      location: location,
    ) else {
      return []
    }
    guard !schemas.isEmpty else {
      throw .invalidKeywordValue(
        keyword,
        location: Self.text(of: location),
      )
    }

    var indexes: [Int] = []
    for (position, schema) in schemas.enumerated() {
      try indexes.append(compileSubschema(
        schema,
        location: location + [keyword, String(position)],
      ))
    }

    return indexes
  }
}
