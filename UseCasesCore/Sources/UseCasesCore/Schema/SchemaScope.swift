/// Where evaluation currently is: which schema document is in force, and where
/// in the DOCUMENT being validated the value sits.
///
/// The root travels with the scope because a `$ref` into another schema file
/// changes what a later `#/$defs/...` reference means.
struct SchemaScope: Sendable {
  let root: JSONValue
  let instancePath: String

  init(
    root: JSONValue,
    instancePath: String = "",
  ) {
    self.root = root
    self.instancePath = instancePath
  }

  /// The same schema document, one step deeper into the data.
  func descending(to segment: String) -> SchemaScope {
    SchemaScope(root: root, instancePath: "\(instancePath)/\(JSONPointer.escape(segment))")
  }

  /// The same schema document, at the array element with this index.
  func descending(toIndex index: Int) -> SchemaScope {
    SchemaScope(root: root, instancePath: "\(instancePath)/\(index)")
  }

  /// A different schema document, at the same place in the data.
  func rooted(at root: JSONValue) -> SchemaScope {
    SchemaScope(root: root, instancePath: instancePath)
  }

  /// A violation raised here.
  func violation(
    _ keyword: String,
    _ message: String,
    missingProperty: String? = nil,
    allowedValues: [JSONValue]? = nil,
  ) -> SchemaViolation {
    SchemaViolation(
      keyword: keyword,
      instancePath: instancePath,
      message: message,
      missingProperty: missingProperty,
      allowedValues: allowedValues,
    )
  }
}
