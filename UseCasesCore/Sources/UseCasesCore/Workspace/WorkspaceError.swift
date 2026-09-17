/// Workspace-resolution failures. The `code` values are frozen public contract
/// (ADR 0007 decision 8): they are what the CLI and the MCP server put on the
/// wire when a workspace cannot be resolved.
public enum WorkspaceError: Error, Equatable, Sendable {
  /// A `--component` was asked for that is not the one `use-cases.yml` declares.
  case unknownComponent(requested: String, declared: String)

  /// `use-cases.yml` is not readable as YAML.
  case configurationParseFailure

  /// `use-cases.yml` parsed, but is not a valid workspace config.
  case configurationSchemaFailure

  /// A path in the config, or derived from it, left the boundary it had to
  /// stay inside. The underlying ``PathError`` keeps its own frozen code.
  case path(PathError)

  /// The stable wire code carried by diagnostics raised from this error.
  public var code: String {
    switch self {
    case .unknownComponent:
      "component.unknown"
    case .configurationParseFailure:
      "workspace_config.parse_error"
    case .configurationSchemaFailure:
      "workspace_config.schema_error"
    case let .path(error):
      error.code
    }
  }

  /// The human-readable message carried alongside the code.
  public var message: String {
    switch self {
    case let .unknownComponent(requested, declared):
      "Unknown component '\(requested)'. Declared component is '\(declared)'."
    case .configurationParseFailure:
      "Unable to parse use-cases.yml."
    case .configurationSchemaFailure:
      "Invalid use-cases.yml."
    case let .path(error):
      error.message
    }
  }
}
