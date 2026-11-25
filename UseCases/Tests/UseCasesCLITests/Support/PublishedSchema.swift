import Foundation

/// A published schema of the design, checked against with the keywords the CLI documents use:
/// `$ref` to another file's definition or property, `type`, `const`, `enum`, `required`,
/// `properties`, `additionalProperties`, `items`, `minLength`, `minItems`, `minimum`, `pattern`,
/// `allOf` and
/// `false` as a schema.
struct PublishedSchema {
  struct Unreadable: Error {
    let reference: String
  }

  private let file: URL
  private let root: JSONValue

  /// Reads the schema at `path` below the `docs` folder.
  init(path: String) throws {
    try self.init(file: DocsFolder.url().appending(path: path))
  }

  private init(file: URL) throws {
    self.file = file
    root = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(contentsOf: file),
    )
  }

  /// Every way `instance` breaks the schema; empty when it holds.
  func failures(of instance: JSONValue) throws -> [String] {
    try failures(
      of: instance,
      against: root,
      at: "$",
    )
  }

  private func failures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) throws -> [String] {
    // `false` as a schema is one nothing satisfies: a property the schema forbids.
    if schema == .boolean(false) {
      return ["\(path): is not allowed here"]
    }

    if case let .string(reference)? = schema["$ref"] {
      let target = try resolve(reference)

      return try target.schema.failures(
        of: instance,
        against: target.node,
        at: path,
      )
    }

    var found: [String] = []

    if let const = schema["const"], const != instance {
      found.append("\(path): not the constant \(const)")
    }

    if case let .array(allowed)? = schema["enum"], !allowed.contains(instance) {
      found.append("\(path): \(instance) is not one of \(allowed)")
    }

    found += typeFailures(of: instance, against: schema, at: path)
    try found += conditionalFailures(of: instance, against: schema, at: path)

    try found += stringFailures(of: instance, against: schema, at: path)
    try found += numberFailures(of: instance, against: schema, at: path)
    try found += objectFailures(of: instance, against: schema, at: path)
    try found += arrayFailures(of: instance, against: schema, at: path)

    return found
  }

  /// `type` as one name or as a list of names, any of which will do.
  private func typeFailures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) -> [String] {
    var names: [String] = []

    switch schema["type"] {
    case let .string(name)?:
      names = [name]
    case let .array(listed)?:
      names = listed.compactMap { value in
        guard case let .string(name) = value else {
          return nil
        }

        return name
      }
    default:
      return []
    }

    let holds = names.contains { name in
      instance.has(type: name)
    }

    return holds ? [] : ["\(path): not of type \(names)"]
  }

  /// `if`, `then` and `else`, and `not` for a list of required members.
  private func conditionalFailures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) throws -> [String] {
    var found: [String] = []

    if case let .array(parts)? = schema["allOf"] {
      for part in parts {
        found += try failures(of: instance, against: part, at: path)
      }
    }

    if case let .array(options)? = schema["oneOf"] {
      var holding = 0

      for option in options where try failures(of: instance, against: option, at: path).isEmpty {
        holding += 1
      }

      if holding != 1 {
        found.append("\(path): matches \(holding) of the oneOf options, not exactly one")
      }
    }

    if let condition = schema["if"] {
      let holds = try failures(of: instance, against: condition, at: path).isEmpty
      let branch = holds ? schema["then"] : schema["else"]

      if let branch {
        found += try failures(of: instance, against: branch, at: path)
      }
    }

    if let forbidden = schema["not"],
       try failures(of: instance, against: forbidden, at: path).isEmpty
    {
      found.append("\(path): matches what the schema forbids")
    }

    return found
  }

  private func stringFailures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) throws -> [String] {
    guard case let .string(text) = instance else {
      return []
    }

    var found: [String] = []

    if case let .integer(least)? = schema["minLength"], text.count < least {
      found.append("\(path): shorter than \(least)")
    }

    if case let .integer(most)? = schema["maxLength"], text.unicodeScalars.count > most {
      found.append("\(path): longer than \(most)")
    }

    if case let .string(pattern)? = schema["pattern"] {
      let expression = try NSRegularExpression(pattern: pattern)
      let whole = NSRange(
        text.startIndex..., in: text,
      )

      if expression.firstMatch(in: text, range: whole) == nil {
        found.append("\(path): '\(text)' does not match \(pattern)")
      }
    }

    return found
  }

  private func numberFailures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) throws -> [String] {
    let value: Double

    switch instance {
    case let .integer(number):
      value = Double(number)
    case let .number(number):
      value = number
    default:
      return []
    }

    var found: [String] = []

    if case let .integer(least)? = schema["minimum"], value < Double(least) {
      found.append("\(path): below \(least)")
    }

    if case let .integer(most)? = schema["maximum"], value > Double(most) {
      found.append("\(path): above \(most)")
    }

    if case let .integer(above)? = schema["exclusiveMinimum"], value <= Double(above) {
      found.append("\(path): not above \(above)")
    }

    return found
  }

  private func objectFailures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) throws -> [String] {
    guard case let .object(members) = instance else {
      return []
    }

    var found: [String] = []

    if case let .array(required)? = schema["required"] {
      for case let .string(name) in required where members[name] == nil {
        found.append("\(path): \(name) is required")
      }
    }

    var properties: [String: JSONValue] = [:]

    if case let .object(declared)? = schema["properties"] {
      properties = declared
    }

    for (name, value) in members.sorted(by: { $0.key < $1.key }) {
      if let names = schema["propertyNames"] {
        found += try failures(
          of: .string(name),
          against: names,
          at: "\(path).\(name) (name)",
        )
      }

      guard let declared = properties[name] else {
        if schema["additionalProperties"] == .boolean(false) {
          found.append("\(path): \(name) is not allowed")
        } else if let extra = schema["additionalProperties"], extra != .boolean(true) {
          found += try failures(
            of: value,
            against: extra,
            at: "\(path).\(name)",
          )
        }

        continue
      }

      try found += failures(
        of: value,
        against: declared,
        at: "\(path).\(name)",
      )
    }

    return found
  }

  private func arrayFailures(
    of instance: JSONValue,
    against schema: JSONValue,
    at path: String,
  ) throws -> [String] {
    guard case let .array(elements) = instance else {
      return []
    }

    var found: [String] = []

    if case let .integer(most)? = schema["maxItems"], elements.count > most {
      found.append("\(path): more than \(most) items")
    }

    if case let .integer(least)? = schema["minItems"], elements.count < least {
      found.append("\(path): fewer than \(least) items")
    }

    guard let items = schema["items"] else {
      return found
    }

    for (index, element) in elements.enumerated() {
      try found += failures(
        of: element,
        against: items,
        at: "\(path)[\(index)]",
      )
    }

    return found
  }

  /// The node a `$ref` names: `<file>#/<pointer>`, the file read beside this one.
  private func resolve(_ reference: String) throws -> (schema: PublishedSchema, node: JSONValue) {
    let parts = reference.components(separatedBy: "#")

    // A reference with no `#` names a whole file.
    guard parts.count <= 2, let location = parts.first else {
      throw Unreadable(reference: reference)
    }

    let schema =
      location.isEmpty
        ? self
        : try PublishedSchema(
          file: file.deletingLastPathComponent().appending(path: location).standardizedFileURL,
        )

    var node = schema.root

    for step in (parts.count == 2 ? parts[1] : "").split(separator: "/") {
      guard let next = node[String(step)] else {
        throw Unreadable(reference: reference)
      }

      node = next
    }

    return (schema, node)
  }
}

private extension JSONValue {
  func has(type: String) -> Bool {
    switch (self, type) {
    case (.string, "string"), (.integer, "integer"), (.boolean, "boolean"), (.array, "array"),
         (.object, "object"), (.null, "null"), (.integer, "number"), (.number, "number"):
      true
    default:
      false
    }
  }
}
