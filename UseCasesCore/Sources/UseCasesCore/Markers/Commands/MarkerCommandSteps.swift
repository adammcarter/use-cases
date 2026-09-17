/// Why a command core stopped before its end: a refusal the result reports
/// with an exit code, or a failure that is thrown to the caller.
enum CommandStop: Error {
  case refused(exitCode: Int, MarkerCommandFailure)
  case failed(MarkerCommandError)
}

/// The steps bind, unbind and rebind are built from, each failing the way the
/// TypeScript's inline version of it fails.
enum MarkerCommandSteps {
  /// `options.suffix ? \`${rowId}#${suffix}\` : rowId` — an empty suffix is
  /// falsy.
  static func bindingSlug(
    rowIdentifier: String,
    suffix: String?,
  ) -> String {
    guard let suffix, !suffix.isEmpty else {
      return rowIdentifier
    }
    return rowIdentifier + "#" + suffix
  }

  static func requireValidSlug(_ bindingSlug: String) throws(CommandStop) {
    guard MarkerSlug.isValid(bindingSlug) else {
      throw .refused(exitCode: 3, MarkerCommandFailure(
        code: "MALFORMED_MARKER",
        message: "binding slug \(bindingSlug) is not a valid use-case slug",
      ))
    }
  }

  static func loadRows(
    context: ResolvedWorkspaceContext,
    registry: SchemaRegistry,
  ) throws(CommandStop) -> LoadedMarkerRows {
    do throws(UseCaseMatrixError) {
      return try MarkerCommandInputs.loadMarkerRows(context: context, registry: registry)
    } catch {
      throw .failed(.useCaseMatrix(error))
    }
  }

  static func requireRow(
    _ loaded: LoadedMarkerRows,
    rowIdentifier: String,
  ) throws(CommandStop) {
    guard MarkerCommandInputs.findRow(loaded.rows, rowIdentifier: rowIdentifier) != nil else {
      throw .refused(exitCode: 2, MarkerCommandFailure(
        code: "ROW_NOT_FOUND",
        message: "row \(rowIdentifier) is not a known use-case row",
      ))
    }
  }

  static func readText(
    _ path: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) -> String? {
    do throws(FileAccessError) {
      return try files.readText(atPath: path)
    } catch {
      throw .failed(.fileAccess(error))
    }
  }

  static func requireSource(
    _ contents: String?,
    relativeFile: String,
  ) throws(CommandStop) -> String {
    guard let contents else {
      throw .refused(exitCode: 2, MarkerCommandFailure(
        code: "FILE_NOT_FOUND",
        message: "source file \(relativeFile) does not exist",
      ))
    }
    return contents
  }

  /// The caller's prefix, or the configured one resolved with the contents so
  /// a shebang script is recognised.
  static func requireCommentPrefix(
    _ explicit: String?,
    relativeFile: String,
    configuration: CommentPrefixConfiguration?,
    contents: String,
  ) throws(CommandStop) -> String {
    let resolved = explicit ?? CommentPrefix.resolve(
      filePath: relativeFile,
      configuration: configuration,
      contents: contents,
    )
    guard let resolved else {
      throw .refused(exitCode: 2, MarkerCommandFailure(
        code: "NO_COMMENT_PREFIX",
        message: "no comment prefix is configured for \(relativeFile); pass --comment-prefix",
      ))
    }
    return resolved
  }

  /// The registry text validated against the loaded rows.
  static func validateRegistry(
    bindingsPath: String,
    files: some MarkerFileSystem,
    loaded: LoadedMarkerRows,
  ) throws(CommandStop) -> RegistryValidationResult {
    let text = try readText(bindingsPath, files: files) ?? ""
    return BindingRegistry.validate(text: text, yamlRowIdentifiers: loaded.rowIdentifiers)
  }

  static func refuseInvalidRegistry(_ errors: [RegistryError]) throws(CommandStop) {
    guard errors.isEmpty else {
      throw .refused(exitCode: 4, MarkerCommandFailure(
        code: "REGISTRY_INVALID",
        message: "binding registry is not valid: " + errors.map(\.message).joined(separator: "; "),
      ))
    }
  }

  static func insertMarker(
    source: String,
    commentPrefix: String,
    bindingSlug: String,
    placement: MarkerPlacement,
  ) throws(CommandStop) -> String {
    switch BindingLifecycle.insertMarkerLines(
      source: source,
      commentPrefix: commentPrefix,
      slug: bindingSlug,
      placement: placement,
    ) {
    case let .refused(failure):
      throw .refused(exitCode: 2, failure)
    case let .contents(contents):
      return contents
    }
  }

  /// Scan the edited file and fail closed: any error tied to the slug, or no
  /// binding for it, refuses with nothing written.
  static func scanPlacedMarker(
    filePath: String,
    contents: String,
    bindingSlug: String,
    configuration: CommentPrefixConfiguration?,
  ) throws(CommandStop) -> PlacedMarkerScan {
    let scan = MarkerScanner.scanFile(
      filePath: filePath,
      contents: contents,
      configuration: configuration,
    )
    let slugError = scan.errors.first { error in
      error.slug.map { slug in
        JavaScriptString.identical(slug, bindingSlug)
      } ?? false
    }
    if let slugError {
      throw .refused(exitCode: 3, MarkerCommandFailure(
        code: slugError.code.rawValue,
        message: slugError.message,
      ))
    }
    let matching = scan.bindings.first { binding in
      JavaScriptString.identical(binding.bindingSlug, bindingSlug)
    }
    guard let matching else {
      throw .refused(exitCode: 3, MarkerCommandFailure(
        code: "MARKER_NOT_RESOLVED",
        message: "the placed marker for \(bindingSlug) did not resolve to a valid span",
      ))
    }
    return PlacedMarkerScan(
      extentKind: matching.extentKind,
      spanStartLine: matching.span.startLine,
      spanEndLine: matching.span.endLine,
      spanSHA256: matching.span.sha256,
    )
  }

  static func findMarker(
    files: some MarkerFileSystem,
    productRoot: String,
    bindingSlug: String,
    configuration: CommentPrefixConfiguration?,
    dataRoot: String,
  ) throws(CommandStop) -> FoundSlugMarker? {
    do throws(FileAccessError) {
      return try BindingLifecycle.findSlugMarker(
        files: files,
        productRoot: productRoot,
        slug: bindingSlug,
        commentConfiguration: configuration,
        skipPaths: [dataRoot],
      )
    } catch {
      throw .failed(.fileAccess(error))
    }
  }

  /// A bound source is rewritten keeping its permission bits, so an executable
  /// script stays executable.
  static func writeSource(
    _ contents: String,
    toPath path: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) {
    do throws(FileAccessError) {
      try files.writeText(contents, toPath: path, preservingMode: true)
    } catch {
      throw .failed(.fileAccess(error))
    }
  }

  static func appendEvent(
    _ event: JSONValue,
    bindingsPath: String,
    files: some MarkerFileSystem,
  ) throws(CommandStop) {
    do throws(FileAccessError) {
      try MarkerCommandFiles.appendJSONLine(
        JSONWriter.encode(event),
        toPath: bindingsPath,
        files: files,
      )
    } catch {
      throw .failed(.fileAccess(error))
    }
  }
}
