import Yams

/// Reads authored YAML with Yams, and holds it to the rules that make every YAML reader agree.
struct StrictYAMLReader: YAMLReading {
  let typer: any PlainScalarTyping
  let commentScanner: any TrailingCommentScanning
  let nestingScanner: any YAMLNestingScanning
  let limits: YAMLReadingLimits

  init(
    typer: any PlainScalarTyping = PlainScalarTyper(),
    commentScanner: any TrailingCommentScanning = TrailingCommentScanner(),
    nestingScanner: any YAMLNestingScanning = YAMLNestingScanner(),
    limits: YAMLReadingLimits = .standard,
  ) {
    self.typer = typer
    self.commentScanner = commentScanner
    self.nestingScanner = nestingScanner
    self.limits = limits
  }

  func read(
    _ text: String,
    file: String,
    kind: AuthoredFileKind,
  ) throws(YAMLReadingError) -> AuthoredValue {
    let body = Self.withoutByteOrderMark(text)
    let context = YAMLReadingContext(
      file: file,
      kind: kind,
      source: YAMLSourceText(body),
    )

    // Composing a very deep file overflows the stack, so the depth is measured first.
    if let line = nestingScanner.firstLine(
      deeperThan: limits.nesting,
      in: context.source,
    ) {
      throw .limitExceeded(
        context.location(line: line),
        .nesting(maximum: limits.nesting),
      )
    }

    guard let root = try composeDocument(body, in: context) else {
      return .object([])
    }

    var state = YAMLConversionState()

    return try convert(
      root,
      in: context,
      state: &state,
    )
  }

  private func composeDocument(
    _ body: String,
    in context: YAMLReadingContext,
  ) throws(YAMLReadingError) -> Node? {
    do {
      return try compose(
        yaml: body,
        .default,
        .default,
        .utf8,
      )
    } catch let error as YamlError {
      throw refusal(for: error, in: context)
    } catch {
      throw .malformed(
        context.location(line: 1),
        problem: "\(error)",
      )
    }
  }

  private func refusal(
    for error: YamlError,
    in context: YAMLReadingContext,
  ) -> YAMLReadingError {
    switch error {
    case let .composer(_, problem, mark, _) where problem == "but found another document":
      .multipleDocuments(context.location(line: mark.line))
    case let .composer(_, problem, mark, _) where problem == "found undefined alias":
      .undefinedAlias(context.location(line: mark.line))
    case let .duplicatedKeysInMapping(duplicates, mapping):
      .duplicateKey(
        context.location(line: mapping.mark.line),
        key: duplicates.first ?? "",
      )
    case let .scanner(parsing, problem, mark, _),
         let .parser(parsing, problem, mark, _),
         let .composer(parsing, problem, mark, _):
      .malformed(
        context.location(line: mark.line),
        problem: Self.describe(
          problem,
          while: parsing,
        ),
      )
    default:
      .malformed(
        context.location(line: 1),
        problem: "\(error)",
      )
    }
  }

  private static func describe(
    _ problem: String,
    while parsing: YamlError.Context?,
  ) -> String {
    guard let parsing else {
      return problem
    }

    return "\(problem) (\(parsing.text))"
  }

  private static func withoutByteOrderMark(_ text: String) -> String {
    guard text.unicodeScalars.first == "\u{FEFF}" else {
      return text
    }

    return String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
  }
}
