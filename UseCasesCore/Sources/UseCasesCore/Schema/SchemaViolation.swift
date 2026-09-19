/// A single broken rule, before it is translated into a ``Diagnostic``.
///
/// This mirrors one AJV `ErrorObject`: the keyword that failed, where in the
/// document it failed, and the raw message AJV would have produced.
struct SchemaViolation: Sendable, Equatable {
  let keyword: String
  let instancePath: String
  let message: String
  let missingProperty: String?
  let allowedValues: [JSONValue]?

  init(
    keyword: String,
    instancePath: String,
    message: String,
    missingProperty: String? = nil,
    allowedValues: [JSONValue]? = nil,
  ) {
    self.keyword = keyword
    self.instancePath = instancePath
    self.message = message
    self.missingProperty = missingProperty
    self.allowedValues = allowedValues
  }
}
