/// One schema object, compiled: the keywords it uses, with every subschema held by the index of
/// its node in a ``SchemaProgram``.
struct SchemaNode: Equatable, Sendable {
  /// A `false` schema: nothing satisfies it.
  var rejectsEverything = false
  /// The types the value may be: any one of them. Empty when `type` is not written.
  var types: [SchemaType] = []
  var reference: Int?
  var constant: AuthoredValue?
  var enumeration: [AuthoredValue]?
  var format: SchemaFormat?

  var pattern: String?
  var minLength: Int?
  var maxLength: Int?
  var minimum: Double?
  var maximum: Double?

  var properties: [ExactText: Int] = [:]
  var required: [String] = []
  var dependentRequired: [ExactText: [String]] = [:]
  var additionalProperties: AdditionalProperties?
  var propertyNames: Int?

  var items: Int?
  var minItems: Int?
  var maxItems: Int?
  var requiresUniqueItems = false

  var allOf: [Int] = []
  var anyOf: [Int] = []
  var oneOf: [Int] = []
  var not: Int?
  var condition: Int?
  var consequence: Int?
  var alternative: Int?
}
