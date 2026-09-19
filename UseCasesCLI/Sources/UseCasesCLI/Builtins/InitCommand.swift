import Foundation
import UseCasesCore

/// `use-cases init` (packages/cli/src/builtins.ts `runInit`): scaffold a workspace.
///
/// A builtin, not a registry command, so its flags are never checked: an
/// unknown one is ignored. `--repo` need not exist; scaffolding creates it.
/// A refused template is an envelope on stdout with exit 2 in either
/// rendering. A blocked scaffold is the envelope with `--json`, otherwise its
/// first message on stderr; it exits 4 for a path escape, else 1. A thrown
/// failure is the standard error envelope with exit 1, as the TypeScript's
/// entry-level catch renders it.
enum InitCommand {
  static func run(
    arguments: [String],
    isJSON: Bool,
    environment: [String: String],
  ) -> CliOutcome {
    let workingDirectory = FileManager.default.currentDirectoryPath
    let repositoryRoot = WorkspacePath.absolute(
      ArgumentScanner.value(after: "--repo", in: arguments) ?? ".",
      relativeTo: workingDirectory,
    )

    var template: InitializationTemplate?
    if let rawTemplate = ArgumentScanner.value(after: "--template", in: arguments) {
      guard let known = InitializationTemplate(rawValue: rawTemplate) else {
        let result = ErrorEnvelope.make(
          command: "init",
          code: "init.unknown_template",
          message: "Unknown --template '\(rawTemplate)'. "
            + "Use one of generic, js-vitest, python-pytest, go-test.",
        )
        return CliOutcome(
          standardOutput: EnvelopeRenderer.render(result.jsonValue(), isJSON: isJSON),
          exitCode: 2,
        )
      }
      template = known
    }

    let scaffold: WorkspaceScaffoldResult
    do throws(WorkspaceScaffoldError) {
      scaffold = try WorkspaceScaffold.scaffold(
        WorkspaceScaffoldOptions(
          repositoryRoot: repositoryRoot,
          template: template,
          component: ArgumentScanner.value(after: "--component", in: arguments),
          force: arguments.contains("--force"),
        ),
        git: ScaffoldGitProcessRunner(environment: environment),
        clock: SystemInitializationClock(),
        currentDirectory: workingDirectory,
      )
    } catch {
      let result = ErrorEnvelope.make(
        command: commandName(arguments),
        code: error.code,
        message: error.message,
      )
      return CliOutcome(
        standardOutput: EnvelopeRenderer.render(result.jsonValue(), isJSON: isJSON),
        exitCode: 1,
      )
    }

    return outcome(scaffold, repositoryRoot: repositoryRoot, isJSON: isJSON)
  }

  private static func outcome(
    _ scaffold: WorkspaceScaffoldResult,
    repositoryRoot: String,
    isJSON: Bool,
  ) -> CliOutcome {
    let isCreated = scaffold.status == .created
    let isPathEscape = scaffold.diagnostics.contains { diagnostic in
      diagnostic.code == "init.path_escape"
    }
    let exitCode: Int32 = isCreated ? 0 : (isPathEscape ? 4 : 1)

    if isJSON {
      let result = CliResult.make(
        command: "init",
        data: scaffold.jsonValue,
        isSuccessful: isCreated,
        isComplete: isCreated,
        diagnostics: scaffold.diagnostics,
        workspaceRoot: repositoryRoot,
        dataRoot: repositoryRoot,
        componentIdentifier: scaffold.componentIdentifier,
      )
      return CliOutcome(
        standardOutput: EnvelopeRenderer.render(result.jsonValue(), isJSON: true),
        exitCode: exitCode,
      )
    }
    guard isCreated else {
      let message = scaffold.diagnostics.first?.message ?? "use-cases init failed."
      return CliOutcome(standardOutput: "", standardError: message + "\n", exitCode: exitCode)
    }
    return CliOutcome(
      standardOutput: summary(scaffold, repositoryRoot: repositoryRoot),
      exitCode: exitCode,
    )
  }

  /// The human summary of a created workspace.
  private static func summary(
    _ scaffold: WorkspaceScaffoldResult,
    repositoryRoot: String,
  ) -> String {
    let agents = scaffold.agentsMarkdown
    let hooks = scaffold.gitHooks
    let hooksPathNote = hooks?.isHooksPathSet == true ? " (core.hooksPath set)" : ""
    let lines = [
      "Scaffolded a Use Cases workspace in \(repositoryRoot)",
      "  template:  \(scaffold.template.rawValue)",
      "  component: \(scaffold.componentIdentifier)",
      "  created:",
    ]
      + scaffold.createdFiles.map { file in
        "    - \(file)"
      }
      + [
        "  AGENTS.md: \(agents?.status.rawValue ?? "untouched") "
          + "(\(agents?.decision.rawValue ?? "-"))",
        "  git hooks: \(hooks?.hooksDirectory ?? "-")\(hooksPathNote)",
        "",
        "Next steps:",
      ]
      + scaffold.nextSteps.enumerated().map { index, step in
        "  \(index + 1). \(step)"
      }
      + [""]
    return lines.joined(separator: "\n") + "\n"
  }

  /// `deriveCommandName`: the leading tokens up to the first flag, dotted.
  private static func commandName(_ arguments: [String]) -> String {
    let tokens = arguments.prefix { token in
      !token.hasPrefix("-")
    }
    return tokens.isEmpty ? "cli" : tokens.joined(separator: ".")
  }
}
