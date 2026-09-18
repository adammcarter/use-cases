import UseCasesCore

/// The usage answer to `--help`, a bare invocation, or a command nothing
/// recognises (packages/cli/src/builtins.ts `runHelp` and `renderHelpText`).
/// Human text by default, the `help` envelope with `--json`; an unrecognised
/// command exits 2 with a `command.unknown` diagnostic.
enum HelpPresenter {
  static func present(
    arguments: [String],
    isUnknown: Bool,
    isJSON: Bool,
  ) -> CliOutcome {
    let tokens = arguments.filter { argument in
      !argument.hasPrefix("-")
    }
    let entries = UsageCatalog.select(tokens: tokens)
    let requested = tokens.isEmpty ? nil : tokens.joined(separator: " ")
    let unknownMessage = "No recognized command for '\(requested ?? "(none)")'. "
      + "See the commands listed below or run `use-cases --help`."
    let exitCode: Int32 = isUnknown ? 2 : 0

    guard isJSON else {
      return CliOutcome(
        standardOutput: text(
          entries: entries,
          requested: requested,
          unknownMessage: isUnknown ? unknownMessage : nil,
        ),
        exitCode: exitCode,
      )
    }

    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("usage", .string("use-cases <command> [subcommand] [flags] --json")),
      ("requested", requested.map(JSONValue.string) ?? .null),
      ("commands", .array(entries.map(\.jsonValue))),
    ]))
    let result = CliResult.make(
      command: "help",
      data: data,
      isSuccessful: !isUnknown,
      isComplete: !isUnknown,
      diagnostics: isUnknown ? [Diagnostic(code: "command.unknown", message: unknownMessage)] : [],
    )
    return CliOutcome(
      standardOutput: EnvelopeRenderer.render(result.jsonValue(), isJSON: true),
      exitCode: exitCode,
    )
  }

  /// A short catalog gets every flag; a long one stays compact.
  static func text(
    entries: [UsageEntry],
    requested: String?,
    unknownMessage: String?,
  ) -> String {
    var lines: [String] = []
    if let unknownMessage {
      lines += ["error: \(unknownMessage)", ""]
    }
    lines += ["use-cases \u{2014} the Use Cases CLI", ""]
    lines += ["Usage: use-cases <command> [subcommand] [flags] [--json]", ""]

    let isDetailed = entries.count <= 3
    if let requested, !requested.isEmpty {
      lines.append("Commands matching '\(requested)':")
    } else {
      lines.append("Commands:")
    }
    let width = min(28, entries.map(\.name.utf16.count).max() ?? 0)
    for entry in entries {
      lines.append("  \(padded(entry.name, to: width))  \(entry.summary)")
      if isDetailed {
        for flag in entry.flags {
          lines.append("      \(padded(flag.flag, to: 34)) \(flag.summary)")
        }
      }
    }

    lines.append("")
    if !isDetailed {
      lines.append("Run `use-cases <command> --help` for that command's flags.")
    }
    lines.append("Add --json to any command for the machine-readable result envelope.")
    return lines.joined(separator: "\n") + "\n"
  }

  /// `String.prototype.padEnd`, counted in UTF-16 units.
  private static func padded(
    _ text: String,
    to width: Int,
  ) -> String {
    text + String(repeating: " ", count: max(0, width - text.utf16.count))
  }
}
