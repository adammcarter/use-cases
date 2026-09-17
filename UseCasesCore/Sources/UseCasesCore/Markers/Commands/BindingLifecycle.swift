/// How a marker is placed.
public enum MarkerMode: String, Equatable, Sendable {
  case explicit
  case swiftFunction = "swift-func"
}

/// Where a marker should go: a single declaration line (swift-func, the marker
/// goes immediately before it) or an inclusive span (explicit, a marker on each
/// side).
public struct MarkerPlacement: Equatable, Sendable {
  public let mode: MarkerMode
  public let line: Int?
  public let startLine: Int?
  public let endLine: Int?

  public init(
    mode: MarkerMode,
    line: Int? = nil,
    startLine: Int? = nil,
    endLine: Int? = nil,
  ) {
    self.mode = mode
    self.line = line
    self.startLine = startLine
    self.endLine = endLine
  }
}

/// One marker occurrence in one file. `endLine` is nil for a lone start marker.
public struct MarkerLocation: Equatable, Sendable {
  public let filePath: String
  public let startLine: Int
  public let endLine: Int?

  public init(
    filePath: String,
    startLine: Int,
    endLine: Int?,
  ) {
    self.filePath = filePath
    self.startLine = startLine
    self.endLine = endLine
  }

  /// `{ file_path, start_line, end_line }`, `end_line` null when absent.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("file_path", .string(filePath)),
      ("start_line", .number(Double(startLine))),
      ("end_line", JSONValue.optionalNumber(endLine)),
    ]))
  }
}

/// The edited contents, or why the edit was refused.
public enum MarkerInsertResult: Equatable, Sendable {
  case contents(String)
  case refused(MarkerCommandFailure)

  /// `{ contents }` or `{ error: { code, message } }`.
  var jsonValue: JSONValue {
    switch self {
    case let .contents(contents):
      .object(JSONObject([("contents", .string(contents))]))
    case let .refused(failure):
      .object(JSONObject([("error", failure.jsonValue)]))
    }
  }
}

/// A slug's marker as found in the product tree, with its file's contents.
public struct FoundSlugMarker: Equatable, Sendable {
  public let location: MarkerLocation
  public let contents: String
  public let commentPrefix: String
}

/// The inputs of a registry event.
public struct RegistryEventInput: Equatable, Sendable {
  public let command: String
  public let rowIdentifier: String
  public let bindingSlug: String
  public let reason: String
  public let eventIdentifier: String
  public let createdAt: String
  /// Nil records ``ProductVersion/version``.
  public let version: String?

  public init(
    command: String,
    rowIdentifier: String,
    bindingSlug: String,
    reason: String,
    eventIdentifier: String,
    createdAt: String,
    version: String? = nil,
  ) {
    self.command = command
    self.rowIdentifier = rowIdentifier
    self.bindingSlug = bindingSlug
    self.reason = reason
    self.eventIdentifier = eventIdentifier
    self.createdAt = createdAt
    self.version = version
  }
}

/// The marker editing and registry-event plumbing shared by the three commands
/// that write a binding (bindingLifecycle.ts): bind places and registers,
/// unbind removes and releases, rebind moves, releases and re-registers.
///
/// Kept in one place because the tool must be the single writer of BOTH halves
/// of a binding — the marker in the source and the event in the registry.
public enum BindingLifecycle {
  /// `insertMarkerLines`: the marker(s) for `slug` inserted at `placement`.
  ///
  /// Lines are split on LF ONLY, so a CRLF source keeps its carriage return on
  /// every line while the inserted marker line has none — mixed endings, as the
  /// TypeScript writes them. The marker is never indented. For an explicit span
  /// the end marker goes in first, at the higher index, so inserting the start
  /// does not shift it.
  public static func insertMarkerLines(
    source: String,
    commentPrefix: String,
    slug: String,
    placement: MarkerPlacement,
  ) -> MarkerInsertResult {
    var (lines, terminator) = splitKeepingTerminator(source)
    let marker = markerToken(commentPrefix) + slug

    switch placement.mode {
    case .swiftFunction:
      guard let line = placement.line, line >= 1 else {
        return .refused(MarkerCommandFailure(
          code: "BIND_LINE_REQUIRED",
          message: "--line is required for swift-func bind",
        ))
      }
      guard line - 1 <= lines.count else {
        return .refused(MarkerCommandFailure(
          code: "BIND_LINE_OUT_OF_RANGE",
          message: "--line \(line) is past end of file",
        ))
      }
      lines.insert(marker, at: line - 1)
      return .contents(joinWithTerminator(lines, terminator))
    case .explicit:
      guard let startLine = placement.startLine, let endLine = placement.endLine else {
        return .refused(MarkerCommandFailure(
          code: "BIND_SPAN_REQUIRED",
          message: "--start-line and --end-line are required for explicit bind",
        ))
      }
      guard startLine >= 1, endLine >= startLine, endLine <= lines.count else {
        return .refused(MarkerCommandFailure(
          code: "BIND_SPAN_OUT_OF_RANGE",
          message: "explicit span \(startLine)-\(endLine) is out of range",
        ))
      }
      lines.insert(markerToken(commentPrefix) + "end " + slug, at: endLine)
      lines.insert(marker, at: startLine - 1)
      return .contents(joinWithTerminator(lines, terminator))
    }
  }

  /// `locateMarkerLines`: the first start marker for `slug` and the first end
  /// marker for it after that start, read from the raw lines rather than the
  /// scanner's records — a marker whose span is BROKEN produces no record, and
  /// that is exactly the state someone needs to release.
  public static func locateMarkerLines(
    filePath: String,
    contents: String,
    commentPrefix: String,
    slug: String,
  ) -> MarkerLocation? {
    let (lines, _) = splitKeepingTerminator(contents)
    var startIndex: Int?
    var endIndex: Int?
    for (index, line) in lines.enumerated() {
      switch MarkerLineParser.parse(line, commentPrefix: commentPrefix) {
      case let .start(parsedSlug, _, _)
        where JavaScriptString.identical(parsedSlug, slug) && startIndex == nil:
        startIndex = index
      case let .end(parsedSlug, _)
        where JavaScriptString.identical(parsedSlug, slug) && startIndex != nil && endIndex == nil:
        endIndex = index
      default:
        continue
      }
    }
    guard let startIndex else {
      return nil
    }
    return MarkerLocation(
      filePath: filePath,
      startLine: startIndex + 1,
      endLine: endIndex.map { $0 + 1 },
    )
  }

  /// `removeMarkerLines`: the lines `location` names dropped; a line number
  /// outside the file drops nothing.
  public static func removeMarkerLines(
    contents: String,
    location: MarkerLocation,
  ) -> String {
    let (lines, terminator) = splitKeepingTerminator(contents)
    var dropped: Set<Int> = [location.startLine - 1]
    if let endLine = location.endLine {
      dropped.insert(endLine - 1)
    }
    let kept = lines.enumerated()
      .filter { line in
        !dropped.contains(line.offset)
      }
      .map(\.element)
    return joinWithTerminator(kept, terminator)
  }

  /// `findSlugMarker`: the slug's marker wherever it sits in the product tree,
  /// in the walk's sorted order, with its file's contents; nil when no file
  /// carries one.
  public static func findSlugMarker(
    files: some MarkerFileSystem,
    productRoot: String,
    slug: String,
    commentConfiguration: CommentPrefixConfiguration? = nil,
    skipPaths: [String] = [],
  ) throws(FileAccessError) -> FoundSlugMarker? {
    let inputs = try MarkerCommandInputs.collectSourceInputs(
      productRoot: productRoot,
      files: files,
      configuration: commentConfiguration,
      skipPaths: skipPaths,
    )
    for input in inputs {
      guard let commentPrefix = CommentPrefix.resolve(
        filePath: input.filePath,
        configuration: commentConfiguration,
        contents: input.contents,
      ) else {
        continue
      }
      if let location = locateMarkerLines(
        filePath: MarkerCommandInputs.toPosix(input.filePath),
        contents: input.contents,
        commentPrefix: commentPrefix,
        slug: slug,
      ) {
        return FoundSlugMarker(
          location: location,
          contents: input.contents,
          commentPrefix: commentPrefix,
        )
      }
    }
    return nil
  }

  /// `bindingRegisteredEvent`.
  public static func bindingRegisteredEvent(_ input: RegistryEventInput) -> JSONValue {
    registryEvent(.bindingRegistered, input)
  }

  /// `bindingReleasedEvent`: the event that ENDS a registration — appended,
  /// never a deletion, so the registry stays append-only.
  public static func bindingReleasedEvent(_ input: RegistryEventInput) -> JSONValue {
    registryEvent(.bindingReleased, input)
  }

  /// The event in the TypeScript's key order. `tool` is the literal
  /// `use-cases`: it is ledger data, frozen with the ledger format.
  private static func registryEvent(
    _ eventType: RegistryEventType,
    _ input: RegistryEventInput,
  ) -> JSONValue {
    .object(JSONObject([
      ("schema", .string(MarkerConstants.bindingRegistrySchemaIdentifier)),
      ("event_type", .string(eventType.rawValue)),
      ("event_id", .string(input.eventIdentifier)),
      ("created_at", .string(input.createdAt)),
      ("created_by", .object(JSONObject([
        ("tool", .string("use-cases")),
        ("command", .string(input.command)),
        ("version", .string(input.version ?? ProductVersion.version)),
      ]))),
      ("row_id", .string(input.rowIdentifier)),
      ("binding_slug", .string(input.bindingSlug)),
      ("reason", .string(input.reason)),
    ]))
  }

  /// `<prefix>: @use-case:` — spelled in two pieces so this source file never
  /// carries a marker line.
  private static func markerToken(_ commentPrefix: String) -> String {
    commentPrefix + ": @use-" + "case:"
  }

  /// Logical lines split on LF code units, and whether the source ended with
  /// one. Worked in code units: a Swift `Character` would fold `\r\n` into one
  /// grapheme and hide both the terminator and the carriage return.
  private static func splitKeepingTerminator(_ source: String)
    -> (lines: [String], terminator: Bool)
  {
    let units = Array(source.utf16)
    guard !units.isEmpty else {
      return ([], false)
    }
    let terminator = units.last == CodeUnits.lineFeed
    let body = terminator ? CodeUnits.string(units.dropLast()) : source
    return (JavaScriptString.split(body, on: CodeUnits.lineFeed), terminator)
  }

  private static func joinWithTerminator(
    _ lines: [String],
    _ terminator: Bool,
  ) -> String {
    let joined = lines.joined(separator: "\n")
    return terminator ? joined + "\n" : joined
  }
}
