import Foundation

/// `use-cases init`: scaffold a minimal, working Use Cases workspace, as
/// `init/scaffold.ts` does.
///
/// Never writes a private key or a workflow file. An existing `use-cases.yml`
/// is refused unless `force` is set, as a `blocked` result. Every scaffold
/// target is checked against the repository root before anything is written;
/// a hook target from a configured `core.hooksPath` is checked only when the
/// hooks are written, and escaping there THROWS, as it does in the TypeScript.
public enum WorkspaceScaffold {
  static let defaultHooksDirectory = ".githooks"

  public static func scaffold(
    _ options: WorkspaceScaffoldOptions,
    git: some ScaffoldGitRunning,
    clock: some InitializationClock,
    currentDirectory: String = FileManager.default.currentDirectoryPath,
  ) throws(WorkspaceScaffoldError) -> WorkspaceScaffoldResult {
    let plan = ScaffoldPlan(options, currentDirectory: currentDirectory)

    let targets: ScaffoldTargets
    do throws(PathError) {
      targets = try ScaffoldTargets(
        repositoryRoot: plan.repositoryRoot,
        templateFiles: ScaffoldTemplates.templateFiles(
          for: plan.template,
          javaScriptVitestRunCommand: plan.javaScriptVitestRunCommand,
        ),
      )
    } catch {
      return plan.result(.blocked, diagnostics: [
        Diagnostic(code: "init.path_escape", message: error.message),
      ])
    }

    if NodeFile.exists(atPath: targets.configurationPath), !options.force {
      return plan.result(.blocked, diagnostics: [Diagnostic(
        code: "init.workspace_exists",
        message: "A workspace config already exists at \(ScaffoldTemplates.configurationFile). "
          + "Re-run with --force to overwrite.",
        sourcePath: ScaffoldTemplates.configurationFile,
      )])
    }

    let files = ScaffoldFiles(repositoryRoot: plan.repositoryRoot)
    try files.makeDirectories(WorkspacePath.dirname(targets.useCasePath))
    try files.write(plan.configuration, to: targets.configurationPath)
    try files.write(ScaffoldTemplates.exampleUseCase, to: targets.useCasePath)
    for file in targets.templatePaths {
      try files.makeDirectories(WorkspacePath.dirname(file.absolutePath))
      try files.write(file.body, to: file.absolutePath)
    }

    let isGitignoreTouched = try files.ensureGitignoreEntries()
    let agentsMarkdown = try files.ensureAgentsMarkdownDecision(today: options.today ?? clock.today)
    let hooks = try files.ensureGitHooks(git: git)

    return plan.result(
      .created,
      createdFiles: [ScaffoldTemplates.configurationFile, ScaffoldTemplates.useCaseFile]
        + targets.templatePaths.map(\.relativePath)
        + (isGitignoreTouched ? [ScaffoldFiles.gitignoreFile] : [])
        + (agentsMarkdown.status == .alreadyRecorded ? [] : [ScaffoldFiles.agentsMarkdownFile])
        + hooks.written,
      agentsMarkdown: agentsMarkdown,
      hooks: hooks,
    )
  }

  /// The steps printed after a scaffold. The hooksPath hint appears only when
  /// the hooks went to the default directory and git was not pointed at it.
  public static func nextSteps(
    hooksPathSet: Bool?,
    hooksDirectory: String?,
  ) -> [String] {
    let hooksHint = hooksPathSet == false && hooksDirectory == defaultHooksDirectory
      ? ["Point git at the hooks once the repo is initialised: "
        + "`git config core.hooksPath .githooks`."]
      : []
    return hooksHint + [
      "Copy use-cases/example.yml's row for your first real use case, then delete the example.",
      "Run `use-cases matrix validate --repo . --json` to confirm the matrix is clean.",
      "Bind the implementing code with `use-cases bind` \u{2014} code-marker grammar in "
        + "docs/markers-adoption.md.",
      "Wire the `acceptance` verifier in use-cases.yml to your real test command (docs/cli.md).",
      "Generate an ed25519 keypair \u{2014} commit the PUBLIC key, keep the PRIVATE key "
        + "in a CI secret only (docs/security.md).",
      "Let trusted CI mint FRESH proofs with `use-cases prove` (docs/cli.md, docs/security.md).",
    ]
  }

  /// `deriveComponentId`: lowercased, split on `.`, each segment's runs outside
  /// `[a-z0-9_-]` made one `-` and its edge `-`/`_` stripped, empty segments
  /// dropped; `workspace` when nothing canonical is left.
  static func componentIdentifier(from raw: String) -> String {
    let segments = raw.lowercased()
      .split(separator: ".", omittingEmptySubsequences: false)
      .map { segment in
        stripEdges(collapseDisallowedRuns(Array(segment.utf16)))
      }
      .filter { segment in
        segment.first.map { unit in
          CodeUnits.isLowercaseASCIILetter(unit) || CodeUnits.isASCIIDigit(unit)
        } ?? false
      }
    let candidate = CodeUnits.string(Array(segments.joined(separator: [0x2E])))
    return CanonicalIdentifier.isValid(candidate) ? candidate : "workspace"
  }

  private static func isAllowed(_ unit: UInt16) -> Bool {
    CodeUnits.isLowercaseASCIILetter(unit) || CodeUnits
      .isASCIIDigit(unit) || unit == 0x5F || unit == 0x2D
  }

  private static func collapseDisallowedRuns(_ units: [UInt16]) -> [UInt16] {
    var result: [UInt16] = []
    var isInRun = false
    for unit in units {
      if isAllowed(unit) {
        result.append(unit)
        isInRun = false
      } else if !isInRun {
        result.append(0x2D)
        isInRun = true
      }
    }
    return result
  }

  private static func stripEdges(_ units: [UInt16]) -> [UInt16] {
    let isEdge = { (unit: UInt16) in
      unit == 0x2D || unit == 0x5F
    }
    return Array(units.drop(while: isEdge).reversed().drop(while: isEdge).reversed())
  }

  /// The last non-empty `/` segment, or `workspace`.
  static func baseName(of repositoryRoot: String) -> String {
    repositoryRoot.split(separator: "/", omittingEmptySubsequences: true).last
      .map(String.init) ?? "workspace"
  }
}

/// Every scaffold target, each checked against the repository root before
/// anything is written.
struct ScaffoldTargets {
  struct TemplateTarget {
    let relativePath: String
    let absolutePath: String
    let body: String
  }

  private static let escapeMessage = "Scaffold target escapes the repo boundary."

  let configurationPath: String
  let useCasePath: String
  let templatePaths: [TemplateTarget]

  init(
    repositoryRoot: String,
    templateFiles: [(relativePath: String, body: String)],
  ) throws(PathError) {
    func contained(_ relativePath: String) throws(PathError) -> String {
      try PathContainment.resolveContained(
        root: repositoryRoot,
        candidate: relativePath,
        message: Self.escapeMessage,
      )
    }
    configurationPath = try contained(ScaffoldTemplates.configurationFile)
    useCasePath = try contained(ScaffoldTemplates.useCaseFile)
    templatePaths = try templateFiles.map { file throws(PathError) in
      try TemplateTarget(
        relativePath: file.relativePath,
        absolutePath: contained(file.relativePath),
        body: file.body,
      )
    }
  }
}

/// What every result of one scaffold shares: the template, the component, the
/// verifier, and the repository they were derived for.
struct ScaffoldPlan {
  let template: InitializationTemplate
  let repositoryRoot: String
  let componentIdentifier: String
  let verifier: ScaffoldTemplates.VerifierPlan
  let javaScriptVitestRunCommand: String

  init(
    _ options: WorkspaceScaffoldOptions,
    currentDirectory: String,
  ) {
    template = options.template ?? .generic
    repositoryRoot = WorkspacePath.absolute(options.repositoryRoot, relativeTo: currentDirectory)
    componentIdentifier = WorkspaceScaffold.componentIdentifier(
      from: options.component ?? WorkspaceScaffold.baseName(of: repositoryRoot),
    )
    verifier = ScaffoldTemplates.defaultVerifier(for: template)
    let root = repositoryRoot
    let packageManager = ScaffoldTemplates.packageManagerLockfiles.first { candidate in
      NodeFile.exists(atPath: root + "/" + candidate.lockfile)
    }?.packageManager
    javaScriptVitestRunCommand = ScaffoldTemplates.javaScriptVitestRunCommand(
      packageManager: packageManager,
    )
  }

  var configuration: String {
    ScaffoldTemplates.configuration(componentIdentifier: componentIdentifier, verifier: verifier)
  }

  func result(
    _ status: WorkspaceScaffoldResult.Status,
    createdFiles: [String] = [],
    agentsMarkdown: AgentsMarkdownOutcome? = nil,
    hooks: ScaffoldFiles.HooksOutcome? = nil,
    diagnostics: [Diagnostic] = [],
  ) -> WorkspaceScaffoldResult {
    WorkspaceScaffoldResult(
      status: status,
      template: template,
      componentIdentifier: componentIdentifier,
      defaultVerifier: verifier.summary,
      createdFiles: createdFiles,
      agentsMarkdown: agentsMarkdown,
      gitHooks: hooks.map { hooks in
        GitHooksOutcome(
          hooksDirectory: hooks.directory,
          isHooksPathSet: hooks.isHooksPathSet,
          extended: hooks.extended,
        )
      },
      nextSteps: hooks.map { hooks in
        WorkspaceScaffold.nextSteps(
          hooksPathSet: hooks.isHooksPathSet,
          hooksDirectory: hooks.directory,
        )
      } ?? [],
      diagnostics: diagnostics,
    )
  }
}
