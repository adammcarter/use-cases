/// The span a placed marker resolved to.
public struct PlacedMarkerScan: Equatable, Sendable {
  public let extentKind: BindingExtentKind
  public let spanStartLine: Int
  public let spanEndLine: Int
  public let spanSHA256: String

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("extent_kind", .string(extentKind.rawValue)),
      ("span_start_line", .number(Double(spanStartLine))),
      ("span_end_line", .number(Double(spanEndLine))),
      ("span_sha256", .string(spanSHA256)),
    ]))
  }
}

public struct BindCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var rowIdentifier: String
  public var suffix: String?
  /// The source file, relative to `productRoot` or absolute.
  public var file: String
  public var mode: MarkerMode
  public var line: Int?
  public var startLine: Int?
  public var endLine: Int?
  public var commentPrefix: String?
  /// Register a marker the caller already placed; no source edit.
  public var registerExisting: Bool
  public var dryRun: Bool
  public var clock: () -> String
  public var identifierFactory: () -> String
  public var version: String?
  public var commentConfiguration: CommentPrefixConfiguration?

  public init(
    context: ResolvedWorkspaceContext,
    productRoot: String,
    bindingsPath: String,
    rowIdentifier: String,
    file: String,
    mode: MarkerMode,
    clock: @escaping () -> String,
    identifierFactory: @escaping () -> String,
  ) {
    self.context = context
    self.productRoot = productRoot
    self.bindingsPath = bindingsPath
    self.rowIdentifier = rowIdentifier
    suffix = nil
    self.file = file
    self.mode = mode
    line = nil
    startLine = nil
    endLine = nil
    commentPrefix = nil
    registerExisting = false
    dryRun = false
    self.clock = clock
    self.identifierFactory = identifierFactory
    version = nil
    commentConfiguration = nil
  }
}

public struct BindCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let rowIdentifier: String
  public let bindingSlug: String
  public let filePath: String
  public let mode: MarkerMode
  public internal(set) var registryEventAppended: Bool
  public let scanResult: PlacedMarkerScan?
  public internal(set) var nextCommand: String?
  public let errors: [MarkerCommandFailure]

  /// The TypeScript result object, in its key order; absent members omitted.
  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("command", .string("bind")),
      ("row_id", .string(rowIdentifier)),
      ("binding_slug", .string(bindingSlug)),
      ("file_path", .string(filePath)),
      ("mode", .string(mode.rawValue)),
      ("exit_code", .number(Double(exitCode))),
      ("ok", .bool(isOK)),
      ("registry_event_appended", .bool(registryEventAppended)),
    ])
    object["scan_result"] = scanResult?.jsonValue
    object["next_command"] = nextCommand.map(JSONValue.string)
    object["errors"] = .array(errors.map(\.jsonValue))
    return .object(object)
  }
}

//: @use-case:lifecycle.signals.bind_names_the_next_step
/// `runBindCommand` (spec 8.1): place and register an identity-only marker,
/// appending ONE `binding_registered` event — and only once the edited source
/// scans clean. It never writes evidence and never accepts a caller's hash.
public enum BindCommand {
  public static func run(
    _ options: BindCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
  ) throws(MarkerCommandError) -> BindCommandResult {
    let bindingSlug = MarkerCommandSteps.bindingSlug(
      rowIdentifier: options.rowIdentifier,
      suffix: options.suffix,
    )
    let relativeFile = MarkerCommandInputs.toPosix(options.file)
    do throws(CommandStop) {
      return try bind(
        options,
        bindingSlug: bindingSlug,
        relativeFile: relativeFile,
        files: files,
        registry: registry,
      )
    } catch {
      switch error {
      case let .failed(failure):
        throw failure
      case let .refused(exitCode, failure):
        return BindCommandResult(
          exitCode: exitCode,
          isOK: false,
          rowIdentifier: options.rowIdentifier,
          bindingSlug: bindingSlug,
          filePath: relativeFile,
          mode: options.mode,
          registryEventAppended: false,
          scanResult: nil,
          nextCommand: nil,
          errors: [failure],
        )
      }
    }
  }

  private static func bind(
    _ options: BindCommandOptions,
    bindingSlug: String,
    relativeFile: String,
    files: some MarkerFileSystem,
    registry: SchemaRegistry,
  ) throws(CommandStop) -> BindCommandResult {
    // 1-2. Slug grammar, then the row must exist.
    try MarkerCommandSteps.requireValidSlug(bindingSlug)
    let loaded = try MarkerCommandSteps.loadRows(context: options.context, registry: registry)
    try MarkerCommandSteps.requireRow(loaded, rowIdentifier: options.rowIdentifier)

    // 3. Read the source first, so a shebang can decide the prefix.
    let absoluteFile = MarkerCommandInputs.resolveUnderRoot(options.productRoot, options.file)
    let current = try MarkerCommandSteps.requireSource(
      MarkerCommandSteps.readText(absoluteFile, files: files),
      relativeFile: relativeFile,
    )
    let commentPrefix = try MarkerCommandSteps.requireCommentPrefix(
      options.commentPrefix,
      relativeFile: relativeFile,
      configuration: options.commentConfiguration,
      contents: current,
    )

    // 4. The append-only registry must already be valid.
    let validation = try MarkerCommandSteps.validateRegistry(
      bindingsPath: options.bindingsPath,
      files: files,
      loaded: loaded,
    )
    try MarkerCommandSteps.refuseInvalidRegistry(validation.errors)
    try refuseDuplicate(validation, bindingSlug: bindingSlug, rowIdentifier: options.rowIdentifier)

    // 5-6. The new source, then its scan; a refusal writes nothing.
    let placed = try place(
      options,
      current: current,
      commentPrefix: commentPrefix,
      bindingSlug: bindingSlug,
      relativeFile: relativeFile,
    )
    var result = BindCommandResult(
      exitCode: 0,
      isOK: true,
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      filePath: relativeFile,
      mode: options.mode,
      registryEventAppended: false,
      scanResult: placed.scan,
      nextCommand: nil,
      errors: [],
    )
    guard !options.dryRun else {
      return result
    }

    // 7. Source first, THEN the registry event (spec 8.1 transactional rule).
    if !options.registerExisting {
      try MarkerCommandSteps.writeSource(placed.contents, toPath: absoluteFile, files: files)
    }
    try register(options, bindingSlug: bindingSlug, files: files)
    result.registryEventAppended = true
    result.nextCommand = "use-cases verify --row \(options.rowIdentifier)"
    return result
  }

  /// The edited source — or the source as it is, for `--register-existing` —
  /// and the span its marker resolves to.
  private static func place(
    _ options: BindCommandOptions,
    current: String,
    commentPrefix: String,
    bindingSlug: String,
    relativeFile: String,
  ) throws(CommandStop) -> (contents: String, scan: PlacedMarkerScan) {
    let contents = options.registerExisting
      ? current
      : try MarkerCommandSteps.insertMarker(
        source: current,
        commentPrefix: commentPrefix,
        bindingSlug: bindingSlug,
        placement: MarkerPlacement(
          mode: options.mode,
          line: options.line,
          startLine: options.startLine,
          endLine: options.endLine,
        ),
      )
    let scan = try MarkerCommandSteps.scanPlacedMarker(
      filePath: relativeFile,
      contents: contents,
      bindingSlug: bindingSlug,
      configuration: options.commentConfiguration,
    )
    return (contents, scan)
  }

  private static func register(
    _ options: BindCommandOptions,
    bindingSlug: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) {
    let event = BindingLifecycle.bindingRegisteredEvent(RegistryEventInput(
      command: "bind",
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      reason: options.registerExisting ? "register_existing" : "initial_bind",
      eventIdentifier: options.identifierFactory(),
      createdAt: options.clock(),
      version: options.version,
    ))
    try MarkerCommandSteps.appendEvent(event, bindingsPath: options.bindingsPath, files: files)
  }

  /// Naming the way out matters here: this refusal is what a wrongly placed
  /// binding hits on the way back in.
  private static func refuseDuplicate(
    _ validation: RegistryValidationResult,
    bindingSlug: String,
    rowIdentifier: String,
  ) throws(CommandStop) {
    guard validation.registry.rowIdentifier(forSlug: bindingSlug) == nil else {
      throw .refused(exitCode: 4, MarkerCommandFailure(
        code: "DUPLICATE_REGISTRATION",
        message: "binding slug \(bindingSlug) is already registered; "
          + "re-point it with `use-cases rebind --row \(rowIdentifier) "
          + "--file <file> --mode <mode>` "
          + "or release it with `use-cases unbind --row \(rowIdentifier)`",
      ))
    }
  }
}

//: @use-case:end lifecycle.signals.bind_names_the_next_step
