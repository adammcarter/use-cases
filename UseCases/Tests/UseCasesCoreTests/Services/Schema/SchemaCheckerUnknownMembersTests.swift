import Testing
@testable import UseCasesCore

struct SchemaCheckerUnknownMembersTests {
  private let schema = #"""
  {"type":"object","additionalProperties":false,"required":["a"],
   "properties":{"a":{"type":"string"},
                 "inner":{"type":"object","additionalProperties":false,
                          "properties":{"b":{"type":"integer"}}},
                 "map":{"type":"object","additionalProperties":{"type":"integer"}}}}
  """#

  @Test(arguments: [
    (#"{"a":"x"}"#, true),
    (#"{"a":"x","extra":1}"#, true),
    (#"{"a":"x","inner":{"b":1,"extra":true}}"#, true),
    (#"{"a":1,"extra":1}"#, false),
    (#"{"extra":1}"#, false),
    (#"{"a":"x","inner":{"b":"no","extra":1}}"#, false),
    (#"{"a":"x","map":{"k":"no"}}"#, false),
    (#"{"a":"x","map":{"k":1}}"#, true),
  ])
  func `an unknown member is ignored and every constraint on a known one holds`(
    value: String,
    isValid: Bool,
  ) throws {
    let checker = try SchemaChecker(
      schema: authored(schema),
      unknownMembers: .ignore,
    )

    #expect(try checker.check(authored(value)).isEmpty == isValid)
  }

  @Test
  func `by default an unknown member is refused`() throws {
    let checker = try SchemaChecker(schema: authored(schema))

    #expect(try checker.check(authored(#"{"a":"x","extra":1}"#)).map(\.keyword) == [
      .additionalProperties,
    ])
  }

  @Test
  func `a definition in another file ignores unknown members too`() throws {
    let shared = try authored(
      #"{"$defs":{"pair":{"type":"object","additionalProperties":false,"required":["a"]}}}"#,
    )
    let checker = try SchemaChecker(
      schema: authored(#"{"$ref":"shared.json#/$defs/pair"}"#),
      documents: ["shared.json": shared],
      unknownMembers: .ignore,
    )

    #expect(try checker.check(authored(#"{"a":1,"b":2}"#)).isEmpty)
    #expect(try checker.check(authored(#"{"b":2}"#)).map(\.keyword) == [.required])
  }
}
