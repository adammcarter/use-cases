/// One file under scan: the marker passes that run over its lines.
struct ScannedFile {
  let filePath: String
  let commentPrefix: String
  let contents: String
  let lines: [PhysicalLine]

  init(
    filePath: String,
    commentPrefix: String,
    contents: String,
  ) {
    self.filePath = filePath
    self.commentPrefix = commentPrefix
    self.contents = contents
    lines = PhysicalLines.split(contents)
  }

  func error(
    _ code: ScanErrorCode,
    _ message: String,
    lineIndex: Int,
    slug: String?,
  ) -> MarkerError {
    MarkerError(code: code, message: message, filePath: filePath, line: lineIndex + 1, slug: slug)
  }

  /// Pass 1: every start and end marker, reporting malformed and forbidden ones.
  func collectMarkers(errors: inout [MarkerError]) -> [MarkerHit] {
    var markers: [MarkerHit] = []
    for (index, line) in lines.enumerated() {
      switch MarkerLineParser.parse(line.text, commentPrefix: commentPrefix) {
      case .none, .ignoreBegin, .ignoreEnd:
        continue
      case let .invalid(code, message, _, slug):
        errors.append(error(.marker(code), message, lineIndex: index, slug: slug))
      case let .start(slug, explicit, column):
        markers.append(MarkerHit(
          lineIndex: index,
          slug: slug,
          column: column,
          explicitStart: explicit,
        ))
      case let .end(slug, column):
        markers.append(MarkerHit(lineIndex: index, slug: slug, column: column, explicitStart: nil))
      }
    }
    return markers
  }

  /// Pass 2: a full start slug may appear once in a file (spec 1.3 rule 2).
  func reportDuplicateStarts(
    _ markers: [MarkerHit],
    errors: inout [MarkerError],
  ) {
    var firstStart: [String: Int] = [:]
    for hit in markers where hit.isStart {
      guard let first = firstStart[hit.slug] else {
        firstStart[hit.slug] = hit.lineIndex
        continue
      }
      errors.append(error(
        .marker(.duplicateBindingSlug),
        "duplicate start marker for slug \(hit.slug) (first at line \(first + 1))",
        lineIndex: hit.lineIndex,
        slug: hit.slug,
      ))
    }
  }

  /// Pass 3: pair starts and ends with a stack. Nested and overlapping spans are
  /// invalid in v1: a matched end that leaves another span open is
  /// `NESTED_SPAN` and suppresses every span involved. Starts never closed are
  /// left for inference.
  func pair(
    _ markers: [MarkerHit],
    errors: inout [MarkerError],
  ) -> MarkerPairing {
    var pairing = MarkerPairing()
    for hit in markers {
      if hit.isStart {
        pairing.unclosedStarts.append(hit)
      } else if let failure = pairing.close(with: hit, in: self) {
        errors.append(failure)
      }
    }
    return pairing
  }
}

/// The running state of pass 3.
struct MarkerPairing {
  /// The open-start stack; whatever remains at the end is a lone start.
  var unclosedStarts: [MarkerHit] = []
  var explicitPairs: [(start: MarkerHit, end: MarkerHit)] = []
  /// Line indexes of starts whose binding a nested span suppressed.
  private var tainted: Set<Int> = []

  mutating func close(
    with end: MarkerHit,
    in file: ScannedFile,
  ) -> MarkerError? {
    guard let start = unclosedStarts.popLast() else {
      return file.error(
        .marker(.endWithoutStart),
        "end marker for \(end.slug) has no matching start",
        lineIndex: end.lineIndex,
        slug: end.slug,
      )
    }
    guard start.slug == end.slug else {
      return file.error(
        .marker(.mismatchedEndMarker),
        "end slug \(end.slug) does not match start slug \(start.slug) "
          + "(line \(start.lineIndex + 1))",
        lineIndex: end.lineIndex,
        slug: end.slug,
      )
    }
    if let container = unclosedStarts.last {
      tainted.insert(start.lineIndex)
      for open in unclosedStarts {
        tainted.insert(open.lineIndex)
      }
      return file.error(
        .marker(.nestedSpan),
        "nested span: \(end.slug) closes inside \(container.slug) "
          + "(line \(container.lineIndex + 1))",
        lineIndex: end.lineIndex,
        slug: end.slug,
      )
    }
    if !tainted.contains(start.lineIndex) {
      explicitPairs.append((start: start, end: end))
    }
    return nil
  }
}
