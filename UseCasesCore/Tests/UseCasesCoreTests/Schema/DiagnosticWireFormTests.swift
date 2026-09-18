import Foundation
import Testing
@testable import UseCasesCore

/// Two traps in the wire form, pinned so a future author hits them here rather
/// than in a shipped envelope.
///
/// `Diagnostic` is `Codable`, and reaching for `JSONEncoder` looks right: it
/// gets every key SPELLING right. It gets the ORDER wrong, because Foundation
/// builds a dictionary and loses the order `encode(to:)` asked for — so only
/// ``Diagnostic/jsonValue`` and ``JSONWriter`` produce the frozen bytes
/// (ADR 0007 decision 8).
///
/// And `expected_state` is the one member of the `schema.validate-fixtures`
/// data block that may VANISH: absent and explicitly-null are two different
/// answers, which is why ``FixtureValidationResult/expectedState`` is an
/// optional `JSONValue` rather than a `JSONValue`.
struct DiagnosticWireFormTests {
  private let frozenKeys = [
    "code",
    "severity",
    "message",
    "source_path",
    "json_pointer",
    "entity_id",
    "related_ids",
  ]

  private var diagnostic: Diagnostic {
    Diagnostic(
      code: "workspace.not_found",
      severity: .warning,
      message: "m",
      sourcePath: "use-cases.yml",
      entityIdentifier: "row.one",
      relatedIdentifiers: ["row.two"],
    )
  }

  @Test
  func `the wire form is the frozen byte sequence`() {
    #expect(
      JSONWriter.encode(diagnostic.jsonValue) == #"""
      {"code":"workspace.not_found","severity":"warning","message":"m",\#
      "source_path":"use-cases.yml","json_pointer":null,"entity_id":"row.one",\#
      "related_ids":["row.two"]}
      """#,
    )
  }

  @Test
  func `the wire form carries the frozen keys in the frozen order`() throws {
    let encoded = JSONWriter.encode(diagnostic.jsonValue)
    let object = try #require(JSONParser.parse(encoded).objectValue)

    #expect(object.keys == frozenKeys)
  }

  @Test
  func `JSONEncoder spells every key right`() throws {
    let data = try JSONEncoder().encode(diagnostic)
    let text = try #require(String(data: data, encoding: .utf8))
    let object = try #require(JSONParser.parse(text).objectValue)

    #expect(Set(object.keys) == Set(frozenKeys))
  }

  @Test
  func `JSONEncoder loses the frozen key order, so it may not build the wire form`() throws {
    let data = try JSONEncoder().encode(diagnostic)
    let text = try #require(String(data: data, encoding: .utf8))
    let object = try #require(JSONParser.parse(text).objectValue)

    #expect(object.keys != frozenKeys)
    #expect(text != JSONWriter.encode(diagnostic.jsonValue))
  }

  @Test
  func `the fixture data block keeps its frozen key order`() {
    let result = FixtureValidationResult(
      isValid: true,
      isComplete: true,
      diagnostics: [],
      validatedSchemaIdentifiers: ["https://use-cases.dev/schemas/v1/common.schema.json"],
      expectedState: .object(JSONObject([("rows", .number(1))])),
    )

    #expect(
      JSONWriter.encode(result.envelopeData(fixture: "fixtures/workspaces/minimal-valid"))
        == #"""
        {"fixture":"fixtures/workspaces/minimal-valid",\#
        "validated_schema_ids":["https://use-cases.dev/schemas/v1/common.schema.json"],\#
        "expected_state":{"rows":1}}
        """#,
    )
  }

  @Test
  func `an absent expected state omits the key entirely`() throws {
    let result = FixtureValidationResult(
      isValid: true,
      isComplete: true,
      diagnostics: [],
      validatedSchemaIdentifiers: [],
      expectedState: nil,
    )
    let object = try #require(result.envelopeData(fixture: "f").objectValue)

    #expect(object.keys == ["fixture", "validated_schema_ids"])
    #expect(object.contains("expected_state") == false)
    #expect(
      JSONWriter.encode(result.envelopeData(fixture: "f"))
        == #"{"fixture":"f","validated_schema_ids":[]}"#,
    )
  }

  @Test
  func `an explicitly null expected state keeps the key with a null value`() throws {
    let result = FixtureValidationResult(
      isValid: true,
      isComplete: true,
      diagnostics: [],
      validatedSchemaIdentifiers: [],
      expectedState: .null,
    )
    let object = try #require(result.envelopeData(fixture: "f").objectValue)

    #expect(object.keys == ["fixture", "validated_schema_ids", "expected_state"])
    #expect(object["expected_state"] == .null)
    #expect(
      JSONWriter.encode(result.envelopeData(fixture: "f"))
        == #"{"fixture":"f","validated_schema_ids":[],"expected_state":null}"#,
    )
  }

  @Test
  func `absent and explicitly null are different wire answers`() {
    let members: (JSONValue?) -> String = { expectedState in
      let result = FixtureValidationResult(
        isValid: true,
        isComplete: true,
        diagnostics: [],
        validatedSchemaIdentifiers: [],
        expectedState: expectedState,
      )
      return JSONWriter.encode(result.envelopeData(fixture: "f"))
    }

    #expect(members(nil) != members(.null))
  }
}
