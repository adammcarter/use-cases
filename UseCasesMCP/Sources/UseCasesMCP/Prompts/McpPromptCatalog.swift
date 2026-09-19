import UseCasesCore

/// The four guided workflows (packages/mcp/src/prompts.ts).
///
/// They explain the real CLI workflow so an agent can drive it through the
/// host. The headline is the KEYLESS DAILY LOOP: bind -> verify -> scan shows
/// local_status VERIFIED_LOCAL, with no keys and no CI. Signing is the opt-in
/// upgrade for a release gate, and `prove` is deliberately absent from the MCP
/// surface — a prompt must not route to it either.
public enum McpPromptCatalog {
  public static let descriptors: [McpPromptDescriptor] = [
    McpPromptDescriptor(
      name: "use-cases/adopt-repo",
      description: "Bring a repository under Use-Case Matrix governance the keyless way: "
        + "author the workspace, bind rows to code, verify, and confirm VERIFIED_LOCAL — then "
        + "add signed CI proofs only when you need a release gate.",
      arguments: [
        McpPromptDescriptor.Argument(
          name: "repo",
          description: "Absolute path to the repository/workspace root.",
        ),
      ],
    ),
    McpPromptDescriptor(
      name: "use-cases/bind-row",
      description: "Bind one matrix row to the code that implements it, verify it, and "
        + "confirm the keyless VERIFIED_LOCAL green — no keys, no CI.",
      arguments: [
        McpPromptDescriptor.Argument(
          name: "row",
          description: "The row id to bind (e.g. auth.login).",
          isRequired: true,
        ),
        McpPromptDescriptor.Argument(
          name: "file",
          description: "Path to the source file that implements the row.",
        ),
        McpPromptDescriptor.Argument(
          name: "repo",
          description: "Absolute path to the repository/workspace root.",
        ),
      ],
    ),
    McpPromptDescriptor(
      name: "use-cases/recover-suspect-row",
      description: "Drive a drifted / unproven row back to green in one command — keyless "
        + "VERIFIED_LOCAL by default, signed FRESH as an opt-in upgrade.",
      arguments: [
        McpPromptDescriptor.Argument(
          name: "row",
          description: "The drifted row id to recover (e.g. auth.login).",
          isRequired: true,
        ),
        McpPromptDescriptor.Argument(
          name: "repo",
          description: "Absolute path to the repository/workspace root.",
        ),
      ],
    ),
    McpPromptDescriptor(
      name: "use-cases/release-review",
      description: "Before a release, confirm every required_for_release row is FRESH and "
        + "the ledger is intact.",
      arguments: [
        McpPromptDescriptor.Argument(
          name: "repo",
          description: "Absolute path to the repository/workspace root.",
        ),
      ],
    ),
  ]

  /// What a `prompts/get` produced: the built prompt, or the JSON-RPC error.
  public enum Outcome: Sendable, Equatable {
    case result(McpPromptResult)
    case failure(code: Int, message: String)
  }

  public static func prompt(
    named name: String,
    arguments: JSONObject,
  ) -> Outcome {
    guard let descriptor = descriptors.first(where: { $0.name == name }) else {
      return .failure(code: -32602, message: "Unknown prompt: \(name)")
    }
    // Only string arguments are read; anything else is as absent as a missing
    // key, and so is an empty string.
    var values: [String: String] = [:]
    for pair in arguments.pairs {
      if let text = pair.value.stringValue {
        values[pair.key] = text
      }
    }
    for argument in descriptor.arguments where argument.isRequired {
      guard let value = values[argument.name], !value.isEmpty else {
        return .failure(
          code: -32602,
          message: "Prompt '\(name)' requires argument '\(argument.name)'.",
        )
      }
    }
    return .result(build(descriptor.name, values))
  }

  /// A placeholder keeps an example command readable when the argument is
  /// absent, rather than printing an empty gap.
  private static func value(
    _ values: [String: String],
    _ name: String,
    placeholder: String,
  ) -> String {
    guard let text = values[name], !text.isEmpty else {
      return placeholder
    }
    return text
  }

  private static func build(
    _ name: String,
    _ values: [String: String],
  ) -> McpPromptResult {
    let repository = value(values, "repo", placeholder: "<repo>")
    let row = value(values, "row", placeholder: "<row-id>")
    return switch name {
    case "use-cases/adopt-repo": adoptRepo(repository)
    case "use-cases/bind-row":
      bindRow(repository, row, value(values, "file", placeholder: "<path/to/source>"))
    case "use-cases/recover-suspect-row": recoverRow(repository, row)
    default: releaseReview(repository)
    }
  }
}
