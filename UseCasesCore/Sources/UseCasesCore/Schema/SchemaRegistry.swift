import Foundation

/// The catalogue of published schemas, and the entry point for validating a
/// document against one of them.
///
/// The ids and their order are frozen contract (ADR 0007 decision 8): the MCP
/// server lists them, the CLI validates against them, and `schema list` prints
/// them in this order.
public struct SchemaRegistry: Sendable {
  /// The schema files, in the order they are published in.
  static let schemaFileNames: [String] = [
    "common.schema.json",
    "cli-result.schema.json",
    "use-case-file.schema.json",
    "evidence-event.schema.json",
    "demo-capsule.schema.json",
    "presentation-plan.schema.json",
    "presentation-plan-result.schema.json",
    "showcase-event.schema.json",
    "showcase-run-status-result.schema.json",
    "showcase-start-result.schema.json",
    "showcase-event-append-result.schema.json",
    "showcase-finish-result.schema.json",
    "showcase-approval-result.schema.json",
    "workspace-config.schema.json",
    "workflow-mode.schema.json",
    "matrix-validation-result.schema.json",
    "matrix-list-result.schema.json",
    "matrix-mutation-result.schema.json",
    "evidence-append-result.schema.json",
    "evidence-status-result.schema.json",
    "migration-test-matrix-result.schema.json",
    "marker.schema.json",
    "release-gate-result.schema.json",
    "ledger.schema.json",
    "keyring.schema.json",
    "authority.schema.json",
    "approval-token.schema.json",
    "mcp-tool-results.schema.json",
  ]

  /// Every published schema id, in frozen order.
  public static let publicSchemaIdentifiers: [String] = schemaFileNames.map {
    schemaIdentifier(forFileName: $0)
  }

  private let schemas: [String: JSONValue]

  /// Load the schema files out of `schemasDirectory`.
  public init(schemasDirectory: URL) throws(SchemaError) {
    var loaded: [String: JSONValue] = [:]
    for fileName in Self.schemaFileNames {
      let fileURL = schemasDirectory.appendingPathComponent(fileName)
      let text: String
      do {
        text = try String(contentsOf: fileURL, encoding: .utf8)
      } catch {
        throw .schemasUnavailable(
          message: "unable to read schema \(fileName) from \(schemasDirectory.path)",
        )
      }
      let schema = try JSONParser.parse(text)
      guard case let .string(identifier)? = schema["$id"] else {
        throw .schemasUnavailable(message: "schema \(fileName) does not declare an $id")
      }
      loaded[identifier] = schema
    }
    schemas = loaded
  }

  /// The id a schema file is published under.
  public static func schemaIdentifier(forFileName fileName: String) -> String {
    "https://use-cases.dev/schemas/v1/\(fileName)"
  }

  /// Resolve a `$ref` document part against the id of the document it sits in.
  static func resolve(
    reference: String,
    against baseIdentifier: String,
  ) -> String? {
    if reference.hasPrefix("https://") || reference.hasPrefix("http://") {
      return reference
    }
    guard !baseIdentifier.isEmpty,
          let base = URL(string: baseIdentifier),
          let resolved = URL(string: reference, relativeTo: base)
    else {
      return nil
    }
    return resolved.absoluteString
  }

  /// Walk up from `startingAt` looking for a `schemas/v1` directory, the way the
  /// TypeScript looks for one relative to its own module.
  public static func locateSchemasDirectory(startingAt: URL) throws(SchemaError) -> URL {
    var directory = startingAt.standardizedFileURL
    while true {
      let candidate = directory.appendingPathComponent("schemas/v1", isDirectory: true)
      let marker = candidate.appendingPathComponent("common.schema.json")
      if FileManager.default.fileExists(atPath: marker.path) {
        return candidate
      }
      let parent = directory.deletingLastPathComponent().standardizedFileURL
      if parent.path == directory.path {
        throw .schemasUnavailable(
          message: "unable to locate schemas/v1 from \(startingAt.path)",
        )
      }
      directory = parent
    }
  }

  /// Load every published schema and check that it resolves — the port of
  /// AJV compiling every schema under `strict: true`.
  public static func validatePublicSchemas(schemasDirectory: URL) -> SchemaCompilationResult {
    do {
      let registry = try SchemaRegistry(schemasDirectory: schemasDirectory)
      let validator = SchemaValidator(registry: registry)
      for identifier in publicSchemaIdentifiers {
        guard let schema = registry.schema(withIdentifier: identifier) else {
          throw SchemaError.schemasUnavailable(message: "schema did not compile: \(identifier)")
        }
        if let problem = validator.compilationProblem(in: schema, root: schema) {
          throw SchemaError.schemasUnavailable(
            message: "schema did not compile: \(identifier): \(problem)",
          )
        }
      }
      return SchemaCompilationResult(
        isValid: true,
        schemaCount: publicSchemaIdentifiers.count,
        diagnostics: [],
      )
    } catch {
      let failure = error as? SchemaError
        ?? SchemaError.schemasUnavailable(message: String(describing: error))
      return SchemaCompilationResult(
        isValid: false,
        schemaCount: 0,
        diagnostics: [
          Diagnostic(code: "schema.compile_failed", message: failure.message),
        ],
      )
    }
  }

  /// The schema published under `identifier`, if it loaded.
  public func schema(withIdentifier identifier: String) -> JSONValue? {
    schemas[identifier]
  }

  /// Every published schema, in frozen order.
  public func publicSchemas() -> [PublicSchema] {
    Self.publicSchemaIdentifiers.map {
      PublicSchema(identifier: $0, schema: schemas[$0])
    }
  }

  /// Validate `value` against the schema published under `schemaIdentifier`.
  public func validate(
    schemaIdentifier: String,
    value: JSONValue,
    sourcePath: String?,
  ) -> ValidationResult {
    guard let schema = schemas[schemaIdentifier] else {
      return ValidationResult(
        isValid: false,
        diagnostics: [
          Diagnostic(
            code: "schema.unknown",
            message: "Unknown schema: \(schemaIdentifier)",
            sourcePath: sourcePath,
          ),
        ],
      )
    }
    let violations = SchemaValidator(registry: self).violations(for: value, against: schema)
    return ValidationResult(
      isValid: violations.isEmpty,
      diagnostics: SchemaDiagnostics.map(violations, sourcePath: sourcePath, document: value),
    )
  }
}
