/// The `keygen` commands, declared for help and flag checking. Their port is
/// ladder row 4c; until it lands each one refuses with `cli_not_yet_ported`.
enum KeygenCommands {
  static let all = [
    keygen,
  ]

  static let keygen = CommandSpecification(
    unportedPath: ["keygen"],
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
    subrow: "4c",
  )
}
