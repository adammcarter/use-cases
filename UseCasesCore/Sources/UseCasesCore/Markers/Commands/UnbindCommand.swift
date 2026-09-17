public struct UnbindCommandOptions {
  public var context: ResolvedWorkspaceContext
  public var productRoot: String
  public var bindingsPath: String
  public var rowIdentifier: String
  public var suffix: String?
  /// Recorded on the release event: why the binding ended.
  public var reason: String?
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
    clock: @escaping () -> String,
    identifierFactory: @escaping () -> String,
  ) {
    self.context = context
    self.productRoot = productRoot
    self.bindingsPath = bindingsPath
    self.rowIdentifier = rowIdentifier
    suffix = nil
    reason = nil
    dryRun = false
    self.clock = clock
    self.identifierFactory = identifierFactory
    version = nil
    commentConfiguration = nil
  }
}

public struct UnbindCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let rowIdentifier: String
  public let bindingSlug: String
  public internal(set) var registryEventAppended: Bool
  /// Empty when the marker was already gone from the source.
  public let markersRemoved: [MarkerLocation]
  public internal(set) var nextCommand: String?
  public let errors: [MarkerCommandFailure]

  /// The TypeScript result object, in its key order; absent members omitted.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("exit_code", .number(Double(exitCode))),
      ("ok", .bool(isOK)),
      ("command", .string("unbind")),
      ("row_id", .string(rowIdentifier)),
      ("binding_slug", .string(bindingSlug)),
      ("registry_event_appended", .bool(registryEventAppended)),
      ("markers_removed", .array(markersRemoved.map(\.jsonValue))),
    ])
    object["next_command"] = nextCommand.map(JSONValue.string)
    object["errors"] = .array(errors.map(\.jsonValue))
    return .object(object)
  }
}

/// `runUnbindCommand`: remove a slug's marker wherever it is and append ONE
/// `binding_released` event, so the slug can be bound again and its row can
/// leave the matrix.
///
/// Deliberately weaker preconditions than bind, because the states worth
/// escaping are the broken ones: the row need not exist, the marker need not
/// exist, and its span need not resolve. The slug must be registered, and every
/// OTHER registry error still fails closed.
public enum UnbindCommand {
  public static func run(
    _ options: UnbindCommandOptions,
    files: some MarkerFileSystem = LocalTextFiles(),
    registry: SchemaRegistry,
  ) throws(MarkerCommandError) -> UnbindCommandResult {
    let bindingSlug = MarkerCommandSteps.bindingSlug(
      rowIdentifier: options.rowIdentifier,
      suffix: options.suffix,
    )
    do throws(CommandStop) {
      return try unbind(options, bindingSlug: bindingSlug, files: files, registry: registry)
    } catch {
      switch error {
      case let .failed(failure):
        throw failure
      case let .refused(exitCode, failure):
        return UnbindCommandResult(
          exitCode: exitCode,
          isOK: false,
          rowIdentifier: options.rowIdentifier,
          bindingSlug: bindingSlug,
          registryEventAppended: false,
          markersRemoved: [],
          nextCommand: nil,
          errors: [failure],
        )
      }
    }
  }

  private static func unbind(
    _ options: UnbindCommandOptions,
    bindingSlug: String,
    files: some MarkerFileSystem,
    registry: SchemaRegistry,
  ) throws(CommandStop) -> UnbindCommandResult {
    try MarkerCommandSteps.requireValidSlug(bindingSlug)
    // Loaded for the ids only: a row that has LEFT the matrix is a reason to
    // unbind, never a reason to refuse.
    let loaded = try MarkerCommandSteps.loadRows(context: options.context, registry: registry)
    let validation = try MarkerCommandSteps.validateRegistry(
      bindingsPath: options.bindingsPath,
      files: files,
      loaded: loaded,
    )
    try MarkerCommandSteps.refuseInvalidRegistry(blockingRegistryErrors(
      validation.errors,
      bindingSlug: bindingSlug,
    ))
    guard validation.registry.rowIdentifier(forSlug: bindingSlug) != nil else {
      throw .refused(exitCode: 2, MarkerCommandFailure(
        code: "NOT_REGISTERED",
        message: "binding slug \(bindingSlug) is not registered, so there is nothing to release",
      ))
    }

    let found = try MarkerCommandSteps.findMarker(
      files: files,
      productRoot: options.productRoot,
      bindingSlug: bindingSlug,
      configuration: options.commentConfiguration,
      dataRoot: options.context.dataRoot,
    )
    var result = UnbindCommandResult(
      exitCode: 0,
      isOK: true,
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      registryEventAppended: false,
      markersRemoved: found.map { marker in
        [marker.location]
      } ?? [],
      nextCommand: nil,
      errors: [],
    )
    guard !options.dryRun else {
      return result
    }

    try release(options, found: found, bindingSlug: bindingSlug, files: files)
    result.registryEventAppended = true
    // A released row proves nothing until it is bound again.
    result.nextCommand = loaded.rowIdentifiers.contains(options.rowIdentifier)
      ? "uc bind --row \(options.rowIdentifier) --file <file> --mode <mode>"
      : "uc scan"
    return result
  }

  /// Source first, then the registry event: a crash between the two leaves an
  /// UNREGISTERED marker (loud), never a registration pointing at nothing.
  private static func release(
    _ options: UnbindCommandOptions,
    found: FoundSlugMarker?,
    bindingSlug: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) {
    if let found {
      try MarkerCommandSteps.writeSource(
        BindingLifecycle.removeMarkerLines(contents: found.contents, location: found.location),
        toPath: MarkerCommandInputs.resolveUnderRoot(options.productRoot, found.location.filePath),
        files: files,
      )
    }
    let event = BindingLifecycle.bindingReleasedEvent(RegistryEventInput(
      command: "unbind",
      rowIdentifier: options.rowIdentifier,
      bindingSlug: bindingSlug,
      reason: options.reason ?? "unbind",
      eventIdentifier: options.identifierFactory(),
      createdAt: options.clock(),
      version: options.version,
    ))
    try MarkerCommandSteps.appendEvent(event, bindingsPath: options.bindingsPath, files: files)
  }

  /// The registry errors unbind runs despite, because releasing this slug is
  /// what CLEARS them: its own missing row or prefix mismatch. Anything else
  /// still fails closed.
  private static func blockingRegistryErrors(
    _ errors: [RegistryError],
    bindingSlug: String,
  ) -> [RegistryError] {
    errors.filter { error in
      let ownSlug = error.bindingSlug.map { slug in
        JavaScriptString.identical(slug, bindingSlug)
      } ?? false
      let selfInflicted = ownSlug
        && (error.code == .registryRowMissing || error.code == .slugPrefixMismatch)
      return !selfInflicted
    }
  }
}
