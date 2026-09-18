public struct RebindCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var rowIdentifier: String
  public var suffix: String?
  /// The NEW home for the marker, relative to `productRoot` or absolute.
  public var file: String
  public var mode: MarkerMode
  public var line: Int?
  public var startLine: Int?
  public var endLine: Int?
  public var reason: String?
  public var commentPrefix: String?
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
    reason = nil
    commentPrefix = nil
    dryRun = false
    self.clock = clock
    self.identifierFactory = identifierFactory
    version = nil
    commentConfiguration = nil
  }
}

public struct RebindCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let rowIdentifier: String
  public let bindingSlug: String
  /// Where the marker ended up.
  public let filePath: String
  public let mode: MarkerMode
  /// Where it came from; nil when the marker was already gone.
  public let movedFrom: MarkerLocation?
  public internal(set) var registryEventsAppended: Int
  public let scanResult: PlacedMarkerScan?
  public internal(set) var nextCommand: String?
  public let errors: [MarkerCommandFailure]

  /// The TypeScript result object, in its key order; absent members omitted.
  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("command", .string("rebind")),
      ("row_id", .string(rowIdentifier)),
      ("binding_slug", .string(bindingSlug)),
      ("file_path", .string(filePath)),
      ("mode", .string(mode.rawValue)),
      ("exit_code", .number(Double(exitCode))),
      ("ok", .bool(isOK)),
      ("moved_from", movedFrom?.jsonValue ?? .null),
      ("registry_events_appended", .number(Double(registryEventsAppended))),
    ])
    object["scan_result"] = scanResult?.jsonValue
    object["next_command"] = nextCommand.map(JSONValue.string)
    object["errors"] = .array(errors.map(\.jsonValue))
    return .object(object)
  }
}

/// `runRebindCommand`: move a binding to the right declaration. The marker
/// moves and the registration moves with it, or neither does.
public enum RebindCommand {
  public static func run(
    _ options: RebindCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
  ) throws(MarkerCommandError) -> RebindCommandResult {
    let bindingSlug = MarkerCommandSteps.bindingSlug(
      rowIdentifier: options.rowIdentifier,
      suffix: options.suffix,
    )
    let relativeFile = MarkerCommandInputs.toPosix(options.file)
    do throws(CommandStop) {
      return try rebind(
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
        return RebindCommandResult(
          exitCode: exitCode,
          isOK: false,
          rowIdentifier: options.rowIdentifier,
          bindingSlug: bindingSlug,
          filePath: relativeFile,
          mode: options.mode,
          movedFrom: nil,
          registryEventsAppended: 0,
          scanResult: nil,
          nextCommand: nil,
          errors: [failure],
        )
      }
    }
  }

  private static func rebind(
    _ options: RebindCommandOptions,
    bindingSlug: String,
    relativeFile: String,
    files: some MarkerFileSystem,
    registry: SchemaRegistry,
  ) throws(CommandStop) -> RebindCommandResult {
    // 1. The registered binding's current marker, anywhere in the product tree.
    let found = try locateRegisteredMarker(
      options,
      bindingSlug: bindingSlug,
      relativeFile: relativeFile,
      files: files,
      registry: registry,
    )

    // 2. Both edits in memory first. When old and new share a file, the
    //    insertion lands on the contents with the old marker already gone,
    //    because that is the file the caller read their line numbers off.
    let move = MarkerMove(found: found, relativeFile: relativeFile, options: options)
    let editedContents = try editTarget(
      options,
      move: move,
      bindingSlug: bindingSlug,
      relativeFile: relativeFile,
      files: files,
    )

    // 3. Validate the NEW placement exactly as bind does.
    var result = try RebindCommandResult(
      exitCode: 0,
      isOK: true,
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      filePath: relativeFile,
      mode: options.mode,
      movedFrom: found?.location,
      registryEventsAppended: 0,
      scanResult: MarkerCommandSteps.scanPlacedMarker(
        filePath: relativeFile,
        contents: editedContents,
        bindingSlug: bindingSlug,
        configuration: options.commentConfiguration,
      ),
      nextCommand: nil,
      errors: [],
    )
    guard !options.dryRun else {
      return result
    }

    // 4. Source first, then release, then re-register.
    try commit(
      options,
      move: move,
      editedContents: editedContents,
      bindingSlug: bindingSlug,
      files: files,
    )
    result.registryEventsAppended = 2
    // The old proof does not survive the move.
    result.nextCommand = "use-cases verify --row \(options.rowIdentifier)"
    return result
  }

  /// Every precondition, in the TypeScript's order, then the marker search.
  private static func locateRegisteredMarker(
    _ options: RebindCommandOptions,
    bindingSlug: String,
    relativeFile: String,
    files: some MarkerFileSystem,
    registry: SchemaRegistry,
  ) throws(CommandStop) -> FoundSlugMarker? {
    try MarkerCommandSteps.requireValidSlug(bindingSlug)
    let loaded = try MarkerCommandSteps.loadRows(context: options.context, registry: registry)
    try MarkerCommandSteps.requireRow(loaded, rowIdentifier: options.rowIdentifier)
    let validation = try MarkerCommandSteps.validateRegistry(
      bindingsPath: options.bindingsPath,
      files: files,
      loaded: loaded,
    )
    try MarkerCommandSteps.refuseInvalidRegistry(validation.errors)
    // Rebind MOVES a binding; a row never bound has nothing to move.
    try refuseUnregistered(
      validation,
      bindingSlug: bindingSlug,
      options: options,
      relativeFile: relativeFile,
    )
    return try MarkerCommandSteps.findMarker(
      files: files,
      productRoot: options.productRoot,
      bindingSlug: bindingSlug,
      configuration: options.commentConfiguration,
      dataRoot: options.context.dataRoot,
    )
  }

  /// The target file — with the old marker already removed when it is the
  /// same file — with the new marker inserted.
  private static func editTarget(
    _ options: RebindCommandOptions,
    move: MarkerMove,
    bindingSlug: String,
    relativeFile: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) -> String {
    let targetBefore = try MarkerCommandSteps.requireSource(
      move.sameFile ? move.removedContents : MarkerCommandSteps.readText(
        move.absoluteTarget,
        files: files,
      ),
      relativeFile: relativeFile,
    )
    let commentPrefix = try MarkerCommandSteps.requireCommentPrefix(
      options.commentPrefix,
      relativeFile: relativeFile,
      configuration: options.commentConfiguration,
      contents: targetBefore,
    )
    return try MarkerCommandSteps.insertMarker(
      source: targetBefore,
      commentPrefix: commentPrefix,
      bindingSlug: bindingSlug,
      placement: MarkerPlacement(
        mode: options.mode,
        line: options.line,
        startLine: options.startLine,
        endLine: options.endLine,
      ),
    )
  }

  /// The old file loses its marker (unless it is the target), the target gains
  /// the new one, then the release and the re-registration are appended.
  private static func commit(
    _ options: RebindCommandOptions,
    move: MarkerMove,
    editedContents: String,
    bindingSlug: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) {
    if let found = move.found, let removedContents = move.removedContents, !move.sameFile {
      try MarkerCommandSteps.writeSource(
        removedContents,
        toPath: MarkerCommandInputs.resolveUnderRoot(options.productRoot, found.location.filePath),
        files: files,
      )
    }
    try MarkerCommandSteps.writeSource(editedContents, toPath: move.absoluteTarget, files: files)
    try appendMoveEvents(options, bindingSlug: bindingSlug, files: files)
  }

  private static func refuseUnregistered(
    _ validation: RegistryValidationResult,
    bindingSlug: String,
    options: RebindCommandOptions,
    relativeFile: String,
  ) throws(CommandStop) {
    guard validation.registry.rowIdentifier(forSlug: bindingSlug) != nil else {
      throw .refused(exitCode: 2, MarkerCommandFailure(
        code: "NOT_REGISTERED",
        message: "binding slug \(bindingSlug) is not registered; bind it first with "
          + "`use-cases bind --row \(options.rowIdentifier) --file \(relativeFile) "
          + "--mode \(options.mode.rawValue)`",
      ))
    }
  }

  /// The release, then the re-registration; each reads the id factory before
  /// the clock, as the TypeScript's object literals do.
  private static func appendMoveEvents(
    _ options: RebindCommandOptions,
    bindingSlug: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) {
    let reason = options.reason ?? "rebind"
    let released = BindingLifecycle.bindingReleasedEvent(RegistryEventInput(
      command: "rebind",
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      reason: reason,
      eventIdentifier: options.identifierFactory(),
      createdAt: options.clock(),
      version: options.version,
    ))
    try MarkerCommandSteps.appendEvent(released, bindingsPath: options.bindingsPath, files: files)
    let registered = BindingLifecycle.bindingRegisteredEvent(RegistryEventInput(
      command: "rebind",
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      reason: reason,
      eventIdentifier: options.identifierFactory(),
      createdAt: options.clock(),
      version: options.version,
    ))
    try MarkerCommandSteps.appendEvent(registered, bindingsPath: options.bindingsPath, files: files)
  }
}

/// Where the old marker is, whether it shares the target file, that file with
/// the marker removed, and where the target file is.
private struct MarkerMove {
  let found: FoundSlugMarker?
  let sameFile: Bool
  let removedContents: String?
  let absoluteTarget: String

  init(
    found: FoundSlugMarker?,
    relativeFile: String,
    options: RebindCommandOptions,
  ) {
    self.found = found
    absoluteTarget = MarkerCommandInputs.resolveUnderRoot(options.productRoot, options.file)
    guard let found else {
      sameFile = false
      removedContents = nil
      return
    }
    sameFile = JavaScriptString.identical(found.location.filePath, relativeFile)
    removedContents = BindingLifecycle.removeMarkerLines(
      contents: found.contents,
      location: found.location,
    )
  }
}
