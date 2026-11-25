import Testing
@testable import UseCasesCore

struct SchemaTypeTests {
  @Test(arguments: [
    (SchemaType.object, AuthoredValue.object([])),
    (.array, .array([])),
    (.string, .string("")),
    (.number, .integer(1)),
    (.number, .number(1.5)),
    (.number, .number(1)),
    (.integer, .integer(1)),
    (.integer, .integer(Int.min)),
    (.integer, .number(1)),
    (.integer, .number(-0.0)),
    (.integer, .number(1e300)),
    (.boolean, .boolean(false)),
    (.null, .null),
  ])
  func `a value is of the type it is`(
    type: SchemaType,
    value: AuthoredValue,
  ) {
    #expect(type.matches(value))
  }

  @Test(arguments: [
    (SchemaType.object, AuthoredValue.array([])),
    (.object, .null),
    (.array, .object([])),
    (.string, .integer(1)),
    (.string, .null),
    (.number, .string("1")),
    (.number, .boolean(true)),
    (.integer, .number(1.5)),
    (.integer, .number(.nan)),
    (.integer, .number(.infinity)),
    (.integer, .string("1")),
    (.integer, .boolean(true)),
    (.boolean, .integer(0)),
    (.boolean, .string("true")),
    (.null, .boolean(false)),
    (.null, .string("")),
  ])
  func `a value is not of any other type`(
    type: SchemaType,
    value: AuthoredValue,
  ) {
    #expect(!type.matches(value))
  }
}
