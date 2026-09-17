/// The `data` block `schema.validate-fixtures` puts on the wire, in the frozen
/// key order (ADR 0007 decision 8).
///
/// `expected_state` is the one member that may VANISH: the TypeScript reads it
/// straight out of a fixture's `expected.json`, so a fixture that declares none
/// leaves it `undefined` and `JSON.stringify` drops the key, while a fixture
/// that declares `null` keeps the key with a null value. Those are two
/// different answers, and ``FixtureValidationResult/expectedState`` carries the
/// difference as nil versus `.null`.
public extension FixtureValidationResult {
  func envelopeData(fixture: String) -> JSONValue {
    var object = JSONObject()
    object["fixture"] = .string(fixture)
    object["validated_schema_ids"] = .array(validatedSchemaIdentifiers.map(JSONValue.string))
    if let expectedState {
      object["expected_state"] = expectedState
    }
    return .object(object)
  }
}
