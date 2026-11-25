import MCP
import Testing
@testable import UseCasesMCP

struct SchemaInlinerTests {
  private static let dialect = Value.string("https://json-schema.org/draft/2020-12/schema")

  private func inlined(
    _ file: String,
    in documents: [String: Value],
  ) throws -> Value {
    try SchemaInliner(documents: documents).inlined(file)
  }

  @Test
  func `a reference to a definition in the same file is replaced by it, and the definitions go`(
  ) throws {
    let result = try inlined("a.json", in: [
      "a.json": .object([
        "$id": .string("https://example.test/a.json"),
        "type": .string("object"),
        "properties": .object(["n": .object(["$ref": .string("#/$defs/count")])]),
        "$defs": .object(["count": .object(["type": .string("integer"), "minimum": .int(0)])]),
      ]),
    ])

    #expect(result == .object([
      "$schema": Self.dialect,
      "type": .string("object"),
      "properties": .object([
        "n": .object(["type": .string("integer"), "minimum": .int(0)]),
      ]),
    ]))
  }

  @Test
  func `a reference into another file, by a path, is replaced by what it points at`() throws {
    let result = try inlined("cli.json", in: [
      "cli.json": .object([
        "properties": .object([
          "id": .object(["$ref": .string("../engine/common.json#/$defs/id")]),
        ]),
      ]),
      "common.json": .object([
        "$defs": .object(["id": .object(["type": .string("string")])]),
      ]),
    ])

    #expect(result.objectValue?["properties"] == .object([
      "id": .object(["type": .string("string")]),
    ]))
  }

  @Test
  func `a pointer into properties and a whole other document are followed`() throws {
    let result = try inlined("cli.json", in: [
      "cli.json": .object([
        "properties": .object([
          "run_id": .object(["$ref": .string("run.json#/properties/run_id")]),
          "result": .object(["$ref": .string("result.json")]),
        ]),
      ]),
      "run.json": .object([
        "$schema": Self.dialect,
        "properties": .object(["run_id": .object(["type": .string("string")])]),
      ]),
      "result.json": .object([
        "$id": .string("x"),
        "$schema": Self.dialect,
        "type": .string("object"),
      ]),
    ])

    #expect(result.objectValue?["properties"] == .object([
      "run_id": .object(["type": .string("string")]),
      "result": .object(["type": .string("object")]),
    ]))
  }

  @Test
  func `a reference inside what is pointed at is read in the file it was written in`() throws {
    let result = try inlined("cli.json", in: [
      "cli.json": .object(["$ref": .string("other.json#/$defs/outer")]),
      "other.json": .object([
        "$defs": .object([
          "outer": .object(["items": .object(["$ref": .string("#/$defs/inner")])]),
          "inner": .object(["type": .string("string")]),
        ]),
      ]),
    ])

    #expect(result.objectValue?["items"] == .object(["type": .string("string")]))
  }

  @Test
  func `what stands beside a reference wins over what it points at`() throws {
    let result = try inlined("a.json", in: [
      "a.json": .object([
        "properties": .object([
          "w": .object([
            "description": .string("mine"),
            "$ref": .string("#/$defs/warnings"),
          ]),
        ]),
        "$defs": .object([
          "warnings": .object(["description": .string("theirs"), "type": .string("array")]),
        ]),
      ]),
    ])

    #expect(result.objectValue?["properties"] == .object([
      "w": .object(["description": .string("mine"), "type": .string("array")]),
    ]))
  }

  @Test
  func `a property that happens to be called $id or $ref is a property, not a keyword`() throws {
    let result = try inlined("a.json", in: [
      "a.json": .object([
        "properties": .object([
          "$id": .object(["type": .string("string")]),
          "$ref": .object(["type": .string("string")]),
        ]),
      ]),
    ])

    #expect(result.objectValue?["properties"] == .object([
      "$id": .object(["type": .string("string")]),
      "$ref": .object(["type": .string("string")]),
    ]))
  }

  @Test
  func `references inside lists are replaced too`() throws {
    let result = try inlined("a.json", in: [
      "a.json": .object([
        "oneOf": .array([
          .object(["$ref": .string("#/$defs/s")]),
          .object(["type": .string("null")]),
        ]),
        "$defs": .object(["s": .object(["type": .string("string")])]),
      ]),
    ])

    #expect(result.objectValue?["oneOf"] == .array([
      .object(["type": .string("string")]),
      .object(["type": .string("null")]),
    ]))
  }

  @Test
  func `a reference that leads back to itself is refused`() {
    #expect(throws: SchemaInliningError.circular("a.json#/$defs/loop")) {
      try inlined("a.json", in: [
        "a.json": .object([
          "$ref": .string("#/$defs/loop"),
          "$defs": .object([
            "loop": .object(["items": .object(["$ref": .string("#/$defs/loop")])]),
          ]),
        ]),
      ])
    }
  }

  @Test
  func `a reference to a file that was not given is refused`() {
    #expect(throws: SchemaInliningError.missingDocument("gone.json")) {
      try inlined("a.json", in: [
        "a.json": .object(["$ref": .string("gone.json#/$defs/x")]),
      ])
    }
  }

  @Test(arguments: ["#/$defs/nothing", "#/properties/0", "#/$defs/s/type/deeper"])
  func `a pointer to a place the file does not have is refused`(reference: String) {
    #expect(throws: SchemaInliningError.self) {
      try inlined("a.json", in: [
        "a.json": .object([
          "properties": .object(["p": .object(["$ref": .string(reference)])]),
          "$defs": .object(["s": .object(["type": .string("string")])]),
        ]),
      ])
    }
  }

  @Test
  func `a file that was not given cannot be inlined`() {
    #expect(throws: SchemaInliningError.missingDocument("nope.json")) {
      try inlined("nope.json", in: [:])
    }
  }

  @Test
  func `a pointer's escapes are read as RFC 6901 says`() throws {
    let result = try inlined("a.json", in: [
      "a.json": .object([
        "$ref": .string("#/$defs/a~1b~0c"),
        "$defs": .object(["a/b~c": .object(["type": .string("string")])]),
      ]),
    ])

    #expect(result.objectValue?["type"] == .string("string"))
  }
}
