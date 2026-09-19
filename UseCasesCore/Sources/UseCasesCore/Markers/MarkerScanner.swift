/// The explicit-span scanner and its Swift inferred-span wiring (spec sections
/// 2, 3, 4.4 and 9).
///
/// Pure: given a path and its contents, find the markers, pair explicit starts
/// and ends, canonicalize each span and emit a binding record per matched span.
/// Every integrity problem is a distinct INVALID with a frozen code; nothing is
/// best-effort. A start with no explicit end goes to the Swift function
/// recognizer in a `.swift` file with the `//` prefix, and is
/// `UNSUPPORTED_INFERENCE` everywhere else. An explicit end always wins.
public enum MarkerScanner {
  public static func scanFile(
    filePath: String,
    contents: String,
    configuration: CommentPrefixConfiguration? = nil,
  ) -> ScanFileResult {
    guard let commentPrefix = CommentPrefix.resolve(
      filePath: filePath,
      configuration: configuration,
      contents: contents,
    ) else {
      return ScanFileResult(filePath: filePath, commentPrefix: nil, bindings: [], errors: [])
    }

    let file = ScannedFile(filePath: filePath, commentPrefix: commentPrefix, contents: contents)
    var errors: [MarkerError] = []
    var bindings: [CurrentBindingRecord] = []

    let markers = file.collectMarkers(errors: &errors)
    file.reportDuplicateStarts(markers, errors: &errors)
    let pairing = file.pair(markers, errors: &errors)

    for pair in pairing.explicitPairs {
      file.buildExplicitRecord(start: pair.start, end: pair.end).record(&bindings, &errors)
    }
    for lone in pairing.unclosedStarts {
      file.resolveLoneStart(lone).record(&bindings, &errors)
    }
    return ScanFileResult(
      filePath: filePath,
      commentPrefix: commentPrefix,
      bindings: bindings,
      errors: errors,
    )
  }

  /// Scan many files, also reporting full start slugs duplicated across the
  /// repository (spec 1.3 rule 2).
  public static func scanFiles(
    _ inputs: [ScanInput],
    configuration: CommentPrefixConfiguration? = nil,
  ) -> ScanResult {
    let files = inputs.map { input in
      scanFile(filePath: input.filePath, contents: input.contents, configuration: configuration)
    }
    let bindings = files.flatMap(\.bindings)
    var errors = files.flatMap(\.errors)

    var firstSeen: [String: CurrentBindingRecord] = [:]
    for binding in bindings {
      guard let prior = firstSeen[binding.bindingSlug] else {
        firstSeen[binding.bindingSlug] = binding
        continue
      }
      errors.append(MarkerError(
        code: .marker(.duplicateBindingSlug),
        message: "duplicate start marker for slug \(binding.bindingSlug) "
          + "across files (first in \(prior.filePath))",
        filePath: binding.filePath,
        line: binding.startMarker.line,
        slug: binding.bindingSlug,
      ))
    }
    return ScanResult(files: files, bindings: bindings, errors: errors)
  }

  /// The spec 8.2 `INFERRED SWIFT SPAN` CI block; nil for an explicit binding.
  public static func formatInferredSwiftSpanReport(_ binding: CurrentBindingRecord) -> String? {
    guard binding.extentKind == .swiftFunctionInferred,
          case let .inferredSwiftFunction(symbolName) = binding.diagnostic
    else {
      return nil
    }
    return [
      "INFERRED SWIFT SPAN",
      "row: \(binding.rowIdentifier)",
      "binding: \(binding.bindingSlug)",
      "file: \(binding.filePath)",
      "symbol: \(symbolName)",
      "span: lines \(binding.span.startLine)-\(binding.span.endLine)",
      "span_sha256: \(binding.span.sha256)",
    ].joined(separator: "\n")
  }
}

/// A start or end marker found on a line.
struct MarkerHit: Equatable {
  let lineIndex: Int
  let slug: String
  let column: Int
  /// Nil for an end marker; for a start, whether it was written `begin <slug>`.
  let explicitStart: Bool?

  var isStart: Bool {
    explicitStart != nil
  }
}

/// Either a binding or the error that prevented it.
enum BindingOutcome {
  case binding(CurrentBindingRecord)
  case error(MarkerError)

  func record(
    _ bindings: inout [CurrentBindingRecord],
    _ errors: inout [MarkerError],
  ) {
    switch self {
    case let .binding(binding):
      bindings.append(binding)
    case let .error(error):
      errors.append(error)
    }
  }
}
