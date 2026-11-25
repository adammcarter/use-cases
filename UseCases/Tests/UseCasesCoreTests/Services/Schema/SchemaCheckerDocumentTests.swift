import Testing
@testable import UseCasesCore

/// A `$ref` to a definition in another schema file, which the results-store schemas use for their
/// shared definitions.
struct SchemaCheckerDocumentTests {
  private let shared = #"""
  {"$defs":{
    "name":{"type":"string","minLength":1},
    "pair":{"type":"object","required":["a"],"properties":{"a":{"$ref":"#/$defs/name"}}},
    "chain":{"$ref":"#/$defs/pair"},
    "loop":{"type":"object","properties":{"next":{"$ref":"#/$defs/loop"}}},
    "unused":{"maxProperties":1}
  }}
  """#

  @Test
  func `a reference to another file's definition is checked against that definition`() throws {
    let checker = try SchemaChecker(
      schema: authored(#"{"$ref":"shared.json#/$defs/name"}"#),
      documents: ["shared.json": authored(shared)],
    )

    #expect(try checker.check(authored(#""x""#)).isEmpty)
    #expect(try checker.check(authored(#""""#)).map(\.keyword) == [.minLength])
    #expect(try checker.check(authored("1")).map(\.keyword) == [.type])
  }

  @Test
  func `a reference inside the other file means that file`() throws {
    let checker = try SchemaChecker(
      schema: authored(#"{"$ref":"shared.json#/$defs/chain","$defs":{"name":{"const":"mine"}}}"#),
      documents: ["shared.json": authored(shared)],
    )

    #expect(try checker.check(authored(#"{"a":"other"}"#)).isEmpty)
    #expect(try checker.check(authored(#"{"a":""}"#)).map(\.pathText) == ["a"])
    #expect(try checker.check(authored("{}")).map(\.keyword) == [.required])
  }

  @Test
  func `a definition that refers to itself compiles`() throws {
    let checker = try SchemaChecker(
      schema: authored(#"{"$ref":"shared.json#/$defs/loop"}"#),
      documents: ["shared.json": authored(shared)],
    )

    #expect(try checker.check(authored(#"{"next":{"next":{}}}"#)).isEmpty)
    #expect(try checker.check(authored(#"{"next":{"next":1}}"#)).map(\.pathText) == ["next/next"])
  }

  @Test
  func `only the definitions a schema names are compiled`() throws {
    _ = try SchemaChecker(
      schema: authored(#"{"$ref":"shared.json#/$defs/name"}"#),
      documents: ["shared.json": authored(shared)],
    )
  }

  @Test
  func `a definition the schema names that uses an unsupported keyword is refused`() throws {
    let value = try authored(#"{"$ref":"shared.json#/$defs/unused"}"#)

    #expect(throws: SchemaCompilerError.unknownKeyword(
      "maxProperties",
      location: "shared.json/$defs/unused",
    )) {
      try SchemaChecker(
        schema: value,
        documents: ["shared.json": authored(shared)],
      )
    }
  }

  @Test(arguments: [
    "shared.json#/$defs/missing",
    "other.json#/$defs/name",
    "shared.json#/definitions/name",
    "shared.json#",
    "shared.json",
  ])
  func `a reference that names nothing in the documents given is refused`(
    reference: String,
  ) throws {
    let value = try authored(JSONMembers(["$ref": "\"\(reference)\""]).json)

    #expect(throws: SchemaCompilerError.unresolvedReference(reference)) {
      try SchemaChecker(
        schema: value,
        documents: ["shared.json": authored(shared)],
      )
    }
  }
}
