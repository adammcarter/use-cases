/// `use-cases keygen` (packages/cli/src/commands/keygen.ts): mint an ed25519 keypair
/// for the opt-in signed proof tier. Run in `KeygenCommands+Run.swift`.
enum KeygenCommands {
  static let all = [
    keygen,
  ]

  static let keygen = CommandSpecification(
    path: ["keygen"],
    command: "markers.keygen",
    summary: "Generate an ed25519 keypair for the opt-in signed proof tier.",
    flags: [
      FlagSpecification(
        key: "repo",
        name: "--repo",
        kind: .string,
        summary: "Workspace root (used only to keep --out outside the tree).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "out",
        name: "--out",
        kind: .string,
        summary: "Write the keypair to <dir> instead of printing it (must be OUTSIDE "
          + "--repo).",
        valueName: "<dir>",
      ),
      FlagSpecification(
        key: "ci",
        name: "--ci",
        kind: .string,
        summary: "Emit a CI setup snippet for <provider> (currently: github).",
        valueName: "<provider>",
      ),
      FlagSpecification(
        key: "json",
        name: "--json",
        kind: .boolean,
        summary: "Emit the machine-readable JSON result envelope.",
      ),
    ],
  ) { context throws(CommandFailure) in
    try run(context)
  }
}
