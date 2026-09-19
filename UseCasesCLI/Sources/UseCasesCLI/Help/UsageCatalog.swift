/// The `--help` catalog (packages/cli/src/command/help-catalog.ts): the
/// hand-written builtins, then every visible registry command projected from
/// its declaration, so help and dispatch can never drift apart.
enum UsageCatalog {
  static let builtins = [
    UsageEntry(
      name: "version",
      summary: "Print the CLI version.",
      flags: [UsageFlag(flag: "--json", summary: "Emit the version envelope.")],
    ),
    UsageEntry(
      name: "init",
      summary: "Scaffold a Use Cases workspace.",
      flags: [
        UsageFlag(flag: "--repo <path>", summary: "Target directory to scaffold into."),
        UsageFlag(
          flag: "--template <name>",
          summary: "generic | js-vitest | python-pytest | go-test.",
        ),
        UsageFlag(flag: "--component <id>", summary: "Component id to seed."),
        UsageFlag(flag: "--force", summary: "Overwrite existing scaffold files."),
        UsageFlag(flag: "--json", summary: "Emit the JSON result envelope."),
      ],
    ),
  ]

  static let entries: [UsageEntry] = builtins + CommandRegistry.allCommands
    .filter { !$0.isHidden }
    .map { command in
      UsageEntry(
        name: command.path.joined(separator: " "),
        summary: command.summary,
        flags: command.flags.filter { !$0.isHidden }.map(UsageFlag.init),
      )
    }

  /// The entries a help request names: those under the full token prefix, else
  /// those in the first token's group, else everything.
  static func select(tokens: [String]) -> [UsageEntry] {
    guard let group = tokens.first else {
      return entries
    }
    let prefixed = entries(under: tokens.joined(separator: " "))
    if !prefixed.isEmpty {
      return prefixed
    }
    let grouped = entries(under: group)
    return grouped.isEmpty ? entries : grouped
  }

  private static func entries(under prefix: String) -> [UsageEntry] {
    entries.filter { entry in
      entry.name == prefix || entry.name.hasPrefix("\(prefix) ")
    }
  }
}
