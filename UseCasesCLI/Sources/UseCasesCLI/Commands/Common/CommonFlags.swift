/// Flags most commands share, defined once so help and parsing never drift
/// (packages/cli/src/commands/common.ts).
enum CommonFlags {
  static let repository = FlagSpecification(
    key: "repo",
    name: "--repo",
    kind: .string,
    summary: "Workspace root (defaults to the current directory).",
    valueName: "<path>",
  )

  static let dataRoot = FlagSpecification(
    key: "dataRoot",
    name: "--data-root",
    kind: .string,
    summary: "Override the data root (must stay inside --repo).",
    valueName: "<path>",
  )

  static let component = FlagSpecification(
    key: "component",
    name: "--component",
    kind: .string,
    summary: "Select a component within the workspace.",
    valueName: "<id>",
  )

  static let json = FlagSpecification(
    key: "json",
    name: "--json",
    kind: .boolean,
    summary: "Emit the machine-readable JSON result envelope (default output is human-readable).",
  )

  /// The workspace-context trio plus `--json`.
  static let workspace = [repository, dataRoot, component, json]
}
