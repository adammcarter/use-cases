/// One schema failure, as AJV reports it: where in the value, and why.
public struct MarkerValidationError: Equatable, Sendable {
  public let instancePath: String
  public let message: String

  /// `{ instance_path, message }`.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("instance_path", .string(instancePath)),
      ("message", .string(message)),
    ]))
  }
}

/// The outcome of validating one value against a marker schema.
public struct MarkerValidationResult: Equatable, Sendable {
  public let isValid: Bool
  public let errors: [MarkerValidationError]

  /// `{ ok, errors }`.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("ok", .bool(isValid)),
      ("errors", .array(errors.map(\.jsonValue))),
    ]))
  }

  /// The errors joined the way registry and evidence diagnostics embed them:
  /// `"<instance_path> <message>"`, trimmed, separated by `"; "`.
  var joinedMessage: String {
    errors
      .map { error in
        JavaScriptString.trim("\(error.instancePath) \(error.message)")
      }
      .joined(separator: "; ")
  }
}

/// The JSON-schema validators for the marker system's own records: binding
/// registry events, proof events and freshness status (validators.ts).
///
/// These schemas are INTERNAL. They are embedded in ``EmbeddedMarkerSchemas``
/// and never registered in ``SchemaRegistry``, whose published catalogue is
/// frozen. Each marker schema resolves its `$ref`s inside its own document, so
/// the evaluator is only borrowed from the schema module.
public enum MarkerSchemaValidation {
  private struct Loaded: Sendable {
    let schemas: [String: JSONValue]
    let validator: SchemaValidator?
  }

  private static let loaded: Loaded = {
    var schemas: [String: JSONValue] = [:]
    for text in EmbeddedMarkerSchemas.byFileName.values {
      if let schema = try? JSONParser.parse(text), let identifier = schema["$id"]?.stringValue {
        schemas[identifier] = schema
      }
    }
    let validator = (try? SchemaRegistry()).map { registry in
      SchemaValidator(registry: registry)
    }
    return Loaded(schemas: schemas, validator: validator)
  }()

  /// Validate `value` against the marker schema with this `$id`.
  public static func validate(
    schemaIdentifier: String,
    value: JSONValue,
  ) -> MarkerValidationResult {
    guard let schema = loaded.schemas[schemaIdentifier], let validator = loaded.validator else {
      return MarkerValidationResult(
        isValid: false,
        errors: [MarkerValidationError(
          instancePath: "",
          message: "unknown schema: \(schemaIdentifier)",
        )],
      )
    }
    let violations = validator.violations(for: value, against: schema)
    return MarkerValidationResult(
      isValid: violations.isEmpty,
      errors: violations.map { violation in
        MarkerValidationError(instancePath: violation.instancePath, message: violation.message)
      },
    )
  }

  public static func validateBindingRegistryEvent(_ value: JSONValue) -> MarkerValidationResult {
    validate(schemaIdentifier: MarkerConstants.bindingRegistrySchemaIdentifier, value: value)
  }

  public static func validateProofEvent(_ value: JSONValue) -> MarkerValidationResult {
    validate(schemaIdentifier: MarkerConstants.evidenceSchemaIdentifier, value: value)
  }

  public static func validateFreshnessStatus(_ value: JSONValue) -> MarkerValidationResult {
    validate(schemaIdentifier: MarkerConstants.statusSchemaIdentifier, value: value)
  }
}
