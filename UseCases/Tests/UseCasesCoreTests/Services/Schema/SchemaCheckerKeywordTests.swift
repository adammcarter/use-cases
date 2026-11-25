import Testing
@testable import UseCasesCore

/// Which keyword a failure names, and how the failures of each keyword read.
struct SchemaCheckerKeywordTests {
  @Test(arguments: [
    (#"{"type":"string"}"#, "1", SchemaKeyword.type),
    (#"{"const":1}"#, "2", .const),
    (#"{"enum":[1]}"#, "2", .enumeration),
    (#"{"format":"date"}"#, #""x""#, .format),
    (#"{"pattern":"^a"}"#, #""b""#, .pattern),
    (#"{"minLength":2}"#, #""b""#, .minLength),
    (#"{"maxLength":1}"#, #""bb""#, .maxLength),
    (#"{"minimum":2}"#, "1", .minimum),
    (#"{"required":["a"]}"#, "{}", .required),
    (#"{"additionalProperties":false}"#, #"{"a":1}"#, .additionalProperties),
    (#"{"propertyNames":{"pattern":"^a"}}"#, #"{"b":1}"#, .propertyNames),
    (#"{"minItems":1}"#, "[]", .minItems),
    (#"{"uniqueItems":true}"#, "[1,1]", .uniqueItems),
    (#"{"anyOf":[{"type":"string"}]}"#, "1", .anyOf),
    (#"{"oneOf":[{"type":"string"}]}"#, "1", .oneOf),
    (#"{"not":{}}"#, "1", .not),
    (#"{"properties":{"a":false}}"#, #"{"a":1}"#, .falseSchema),
  ])
  func `a failure names the keyword that failed and reads as not allowed where it must`(
    schema: String,
    value: String,
    keyword: SchemaKeyword,
  ) throws {
    let checker = try SchemaChecker(schema: authored(schema))

    let failures = try checker.check(authored(value))

    #expect(failures.map(\.keyword) == [keyword])
    let readsAsNotAllowed: Set<SchemaKeyword> = [
      .const, .enumeration, .pattern, .propertyNames, .anyOf, .oneOf, .not, .falseSchema,
    ]
    let isNotAllowed = failures.allSatisfy {
      $0.message.hasSuffix("is not allowed")
    }
    #expect(isNotAllowed == readsAsNotAllowed.contains(keyword))
  }
}
