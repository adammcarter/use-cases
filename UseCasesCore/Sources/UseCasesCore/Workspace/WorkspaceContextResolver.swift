import Foundation

/// Resolves the roots every command works against: the workspace, the data
/// root, the use-cases root, the component, and where each answer came from.
///
/// This is the port of `packages/core/src/roots.ts`. The provenance block, the
/// refusal of an unknown component, the containment of `use_cases_dir` inside
/// `data_root`, and the fact that a missing `use-cases.yml` yields a null config
/// path with defaults are all behaviour the TypeScript suite pins.
public enum WorkspaceContextResolver {
  /// Canonical diagnostic code for a workspace root that does not exist on
  /// disk. Single source of truth so the CLI and the MCP server emit the same
  /// code (ADR 0007 decision 8).
  public static let workspaceNotFoundCode = "workspace.not_found"

  /// The id of the schema `use-cases.yml` is validated against.
  static let configurationSchemaIdentifier = SchemaRegistry
    .schemaIdentifier(forFileName: "workspace-config.schema.json")

  /// The workspace-relative name of the config file.
  static let configurationFileName = "use-cases.yml"

  /// A `use-cases.yml` that parsed and validated, and whatever validating it
  /// reported.
  struct Configuration {
    let value: JSONObject
    let diagnostics: [Diagnostic]
  }

  /// The three roots a config may declare, read out once.
  private struct Declared {
    let component: String?
    let dataRoot: String?
    let useCasesDirectory: String?

    init(_ configuration: JSONObject?) {
      component = configuration?["component_id"]?.stringValue
      dataRoot = configuration?["data_root"]?.stringValue
      useCasesDirectory = configuration?["use_cases_dir"]?.stringValue
    }
  }

  /// Resolve every root, reading `use-cases.yml` when the workspace has one.
  ///
  /// `registry` validates the config. It is passed in rather than built here so
  /// a caller loads the embedded schemas once and threads them everywhere.
  public static func resolve(
    options: ResolveWorkspaceContextOptions = ResolveWorkspaceContextOptions(),
    registry: SchemaRegistry,
  ) throws(WorkspaceError) -> ResolvedWorkspaceContext {
    let workspaceRoot = resolvedWorkspaceRoot(options.workspaceRoot)
    let configurationPath = WorkspacePath.absolute(
      configurationFileName,
      relativeTo: workspaceRoot,
    )
    let hasConfiguration = FileManager.default.fileExists(atPath: configurationPath)
    let configuration = hasConfiguration
      ? try readConfiguration(
        atPath: configurationPath,
        workspaceRoot: workspaceRoot,
        registry: registry,
      )
      : nil
    let declared = Declared(configuration?.value)

    try refuseUnknownComponent(option: options.component, declared: declared.component)

    let dataRoot = WorkspacePath.realpathIfExists(
      resolveRelative(
        root: workspaceRoot,
        value: options.dataRootOverride ?? declared.dataRoot ?? ".",
      ),
    )
    let useCasesRoot = resolveRelative(
      root: dataRoot,
      value: declared.useCasesDirectory ?? "use-cases",
    )
    try refuseEscapingUseCasesRoot(dataRoot: dataRoot, useCasesRoot: useCasesRoot)

    return ResolvedWorkspaceContext(
      pluginRoot: WorkspacePath.realpathIfExists(options.pluginRoot ?? findPluginRoot()),
      workspaceRoot: workspaceRoot,
      dataRoot: dataRoot,
      useCasesRoot: useCasesRoot,
      componentIdentifier: options.component ?? declared.component
        ?? ProductVersion.defaultComponentIdentifier,
      configPath: hasConfiguration ? configurationFileName : nil,
      verifiers: ResolvedWorkspaceVerifiers.normalize(configuration?.value["verifiers"]),
      releaseGate: WorkspaceReleaseGate.normalize(configuration?.value["release_gate"]),
      approvalTrust: WorkspaceApprovalTrust.normalize(configuration?.value["approval_trust"]),
      provenance: provenance(options: options, declared: declared),
      diagnostics: configuration?.diagnostics ?? [],
    )
  }

  /// Which input decided each root. An option that is present but EMPTY still
  /// decides the path and yet claims no origin, because the TypeScript tests
  /// truthiness here and `??` there.
  private static func provenance(
    options: ResolveWorkspaceContextOptions,
    declared: Declared,
  ) -> WorkspaceProvenance {
    WorkspaceProvenance(
      workspaceRoot: isTruthy(options.workspaceRoot) ? .explicit : .currentDirectory,
      dataRoot: dataRootProvenance(
        override: options.dataRootOverride,
        declared: declared.dataRoot,
      ),
      useCasesRoot: isTruthy(declared.useCasesDirectory) ? .workspaceConfig : .default,
      componentIdentifier: componentProvenance(
        option: options.component,
        declared: declared.component,
      ),
    )
  }

  /// The workspace root, made absolute against the working directory and then
  /// resolved through its symlinks.
  private static func resolvedWorkspaceRoot(_ requested: String?) -> String {
    let workingDirectory = FileManager.default.currentDirectoryPath
    return WorkspacePath.realpathIfExists(
      WorkspacePath.absolute(requested ?? workingDirectory, relativeTo: workingDirectory),
    )
  }

  /// A `--component` that contradicts the declared one is a typo, not a second
  /// component: the workspace declares exactly one.
  private static func refuseUnknownComponent(
    option: String?,
    declared: String?,
  ) throws(WorkspaceError) {
    guard isTruthy(option), isTruthy(declared),
          let requested = option, let declared, requested != declared
    else {
      return
    }
    throw .unknownComponent(requested: requested, declared: declared)
  }

  /// The use-cases root always sits inside the data root.
  private static func refuseEscapingUseCasesRoot(
    dataRoot: String,
    useCasesRoot: String,
  ) throws(WorkspaceError) {
    do {
      try ensureContained(
        root: dataRoot,
        child: useCasesRoot,
        message: "use_cases_dir escapes data_root",
      )
    } catch {
      throw .path(error)
    }
  }

  /// The shared READ-side workspace-existence guard.
  ///
  /// A non-existent workspace root is a user typo, NOT a valid empty workspace:
  /// without this guard the read-only inspection surface reports a missing path
  /// as a clean, valid, zero-use-case matrix — a silent wrong answer. An
  /// existing-but-empty directory is still legitimate. `workspaceRoot` must
  /// already be absolute.
  public static func workspaceNotFoundDiagnostic(workspaceRoot: String) -> Diagnostic? {
    guard !FileManager.default.fileExists(atPath: workspaceRoot) else {
      return nil
    }
    return Diagnostic(
      code: workspaceNotFoundCode,
      message: "repo path does not exist: \(workspaceRoot)",
    )
  }

  /// The checkout carrying `.claude-plugin/plugin.json`, found by walking up
  /// from `origin` — so the answer is the same however the binary was invoked.
  ///
  /// The TypeScript walks up from its own module URL. A compiled binary has no
  /// module URL, so the walk starts from the executable's own directory; the
  /// algorithm (at most six directories, then three levels up as a fallback) is
  /// the TypeScript's unchanged.
  public static func findPluginRoot(
    startingAt origin: String = executableDirectory,
  ) -> String {
    var directory = origin
    for _ in 0 ..< 6 {
      let manifest = directory + "/.claude-plugin/plugin.json"
      if FileManager.default.fileExists(atPath: manifest) {
        return directory
      }
      let parent = WorkspacePath.dirname(directory)
      if parent == directory {
        break
      }
      directory = parent
    }
    return WorkspacePath.absolute("../../..", relativeTo: origin)
  }

  /// The directory the running executable sits in.
  public static var executableDirectory: String {
    let workingDirectory = FileManager.default.currentDirectoryPath
    let executable = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "."
    return WorkspacePath.dirname(
      WorkspacePath.absolute(executable, relativeTo: workingDirectory),
    )
  }

  /// Refuse a `child` that is not `root` or beneath it.
  ///
  /// Defence in depth: a schema-valid `use_cases_dir` is already relative and
  /// free of `..`, so it cannot escape — but the guard stands where the
  /// TypeScript's stands, because the config is hand-edited.
  static func ensureContained(
    root: String,
    child: String,
    message: String,
  ) throws(PathError) {
    guard WorkspacePath.isContained(root: root, child: child) else {
      throw .escape(message)
    }
  }

  /// Refuse a config value that is absolute, or that carries a `..` segment
  /// past EITHER separator — the schema's pattern only knows about `/`, so a
  /// backslash-separated `..` reaches here.
  static func ensureRelativeSafe(_ value: String) throws(PathError) {
    let segments = value.split(whereSeparator: { character in
      character == "/" || character == "\\"
    })
    guard !WorkspacePath.isAbsolute(value), !segments.contains("..") else {
      throw .escape("Unsafe relative path '\(value)'.")
    }
  }

  /// An absolute value stands as it is; anything else hangs off `root`.
  static func resolveRelative(
    root: String,
    value: String,
  ) -> String {
    WorkspacePath.absolute(value, relativeTo: root)
  }

  // MARK: - The config file

  /// Read, parse and validate `use-cases.yml`, refusing anything unsafe in it.
  static func readConfiguration(
    atPath configurationPath: String,
    workspaceRoot: String,
    registry: SchemaRegistry,
  ) throws(WorkspaceError) -> Configuration {
    // The TypeScript lets a read failure escape as a raw filesystem error. A
    // typed throw has to name one, and the file HAS just been seen to exist, so
    // an unreadable one is reported as the config being unreadable.
    guard let source = try? String(contentsOfFile: configurationPath, encoding: .utf8) else {
      throw .configurationParseFailure
    }
    let parsed = YamlParser.parseToJSON(source: source, sourcePath: configurationFileName)
    guard parsed.isValid, let value = parsed.value else {
      throw .configurationParseFailure
    }
    let validation = registry.validate(
      schemaIdentifier: configurationSchemaIdentifier,
      value: value,
      sourcePath: configurationFileName,
    )
    guard validation.isValid, let object = value.objectValue else {
      throw .configurationSchemaFailure
    }
    try ensureConfigurationPathsAreSafe(object)

    let sourcePath = relativePath(of: configurationPath, in: workspaceRoot)
    return Configuration(
      value: object,
      diagnostics: validation.diagnostics.map { diagnostic in
        reported(diagnostic, at: sourcePath)
      },
    )
  }

  /// Every path a config may name has to stay relative and inside.
  private static func ensureConfigurationPathsAreSafe(
    _ object: JSONObject,
  ) throws(WorkspaceError) {
    let candidates = [
      object["data_root"]?.stringValue,
      object["use_cases_dir"]?.stringValue,
      object["approval_trust"]?["keyring_path"]?.stringValue,
    ]
    for candidate in candidates where isTruthy(candidate) {
      guard let candidate else {
        continue
      }
      do {
        try ensureRelativeSafe(candidate)
      } catch {
        throw .path(error)
      }
    }
  }

  /// The same diagnostic, reported against the config's workspace-relative
  /// path rather than whatever the validator was handed.
  private static func reported(
    _ diagnostic: Diagnostic,
    at sourcePath: String,
  ) -> Diagnostic {
    Diagnostic(
      code: diagnostic.code,
      severity: diagnostic.severity,
      message: diagnostic.message,
      sourcePath: sourcePath,
      jsonPointer: diagnostic.jsonPointer,
      sourceSpan: diagnostic.sourceSpan,
      entityIdentifier: diagnostic.entityIdentifier,
      relatedIdentifiers: diagnostic.relatedIdentifiers,
    )
  }

  /// `path` spelled relative to `root`, with `/` separators.
  private static func relativePath(
    of path: String,
    in root: String,
  ) -> String {
    let boundary = root.hasSuffix("/") ? root : root + "/"
    guard path.hasPrefix(boundary) else {
      return path
    }
    return String(path.dropFirst(boundary.count))
  }

  // MARK: - Provenance

  /// JavaScript truthiness for the strings this port reads: present AND not
  /// empty. The TypeScript's provenance block asks `value ? ... : ...`, so an
  /// empty option claims no origin even though it still decides the path.
  static func isTruthy(_ value: String?) -> Bool {
    guard let value else {
      return false
    }
    return !value.isEmpty
  }

  private static func dataRootProvenance(
    override: String?,
    declared: String?,
  ) -> DataRootProvenance {
    if isTruthy(override) {
      return .override
    }
    return isTruthy(declared) ? .workspaceConfig : .default
  }

  private static func componentProvenance(
    option: String?,
    declared: String?,
  ) -> ComponentIdentifierProvenance {
    if isTruthy(option) {
      return .option
    }
    return isTruthy(declared) ? .workspaceConfig : .default
  }
}
