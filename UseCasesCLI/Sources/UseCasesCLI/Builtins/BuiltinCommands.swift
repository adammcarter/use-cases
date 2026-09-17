import UseCasesCore

/// What stays outside the registry (packages/cli/src/builtins.ts): version,
/// help, `init`, and the usage answer for anything unrecognised.
///
/// The TypeScript also carries `schema list` and `schema validate-fixtures`
/// branches here; the registry always matches those first, so they can never
/// run and are not ported.
enum BuiltinCommands {
  static func run(arguments: [String]) -> CliOutcome {
    let normalized = CommandLineInterface.normalized(arguments)
    let isJSON = normalized.contains("--json")

    if normalized.contains("--version") || normalized.contains("-v") || normalized
      .first == "version"
    {
      return version(isJSON: isJSON)
    }
    if normalized.isEmpty || normalized.contains("--help") || normalized.contains("-h") {
      return HelpPresenter.present(arguments: normalized, isUnknown: false, isJSON: isJSON)
    }
    if normalized.first == "init" {
      let output = NotYetPorted.output(command: "init", invocation: "init", subrow: "4b")
      return CliOutcome(
        standardOutput: EnvelopeRenderer.render(output.envelope, isJSON: isJSON),
        exitCode: output.exitCode,
      )
    }
    return HelpPresenter.present(arguments: normalized, isUnknown: true, isJSON: isJSON)
  }

  private static func version(isJSON: Bool) -> CliOutcome {
    guard isJSON else {
      return CliOutcome(standardOutput: ProductVersion.version + "\n", exitCode: 0)
    }
    let info = ProductVersion.versionInfo()
    let result = CliResult.make(
      command: "version",
      data: .object(JSONObject([("name", .string(info.name)), ("version", .string(info.version))])),
    )
    return CliOutcome(
      standardOutput: EnvelopeRenderer.render(result.jsonValue(), isJSON: true),
      exitCode: 0,
    )
  }
}
