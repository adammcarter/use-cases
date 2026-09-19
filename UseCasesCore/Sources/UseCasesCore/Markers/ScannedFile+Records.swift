extension ScannedFile {
  /// The binding record for a matched explicit pair. The span is the complete
  /// lines strictly between the markers, minus ignore regions.
  func buildExplicitRecord(
    start: MarkerHit,
    end: MarkerHit,
  ) -> BindingOutcome {
    let firstBody = start.lineIndex + 1
    let lastBody = end.lineIndex - 1

    var bodyTexts: [String] = []
    var startByte = lines[start.lineIndex].byteEnd
    var endByte = startByte
    if firstBody <= lastBody {
      do throws(UnbalancedIgnore) {
        bodyTexts = try bodyTextsExcludingIgnoreRegions(
          firstBody: firstBody,
          lastBody: lastBody,
          slug: start.slug,
        )
      } catch {
        return .error(error.markerError)
      }
      startByte = lines[firstBody].byteStart
      endByte = lines[lastBody].byteEnd
    }

    // For adjacent markers `endLine` is `startLine - 1`: the empty-span signal.
    let span = BindingSpan(
      startLine: firstBody + 1,
      endLine: lastBody + 1,
      startByte: startByte,
      endByte: endByte,
      sha256: SpanCanonicalizer.hash(bodyTexts),
    )
    return .binding(record(
      start: start,
      extentKind: .explicit,
      endMarker: MarkerPosition(line: end.lineIndex + 1, column: end.column),
      span: span,
      diagnostic: .explicit,
    ))
  }

  private func bodyTextsExcludingIgnoreRegions(
    firstBody: Int,
    lastBody: Int,
    slug: String,
  ) throws(UnbalancedIgnore) -> [String] {
    var texts: [String] = []
    var openIgnoreLine: Int?
    for index in firstBody ... lastBody {
      switch MarkerLineParser.parse(lines[index].text, commentPrefix: commentPrefix) {
      case .ignoreBegin:
        guard openIgnoreLine == nil else {
          throw unbalancedIgnore(
            "nested ignore region inside \(slug); "
              + "close the current ignore region before starting another",
            lineIndex: index,
            slug: slug,
          )
        }
        openIgnoreLine = index
      case .ignoreEnd:
        guard openIgnoreLine != nil else {
          throw unbalancedIgnore(
            "ignore end inside \(slug) has no matching ignore begin",
            lineIndex: index,
            slug: slug,
          )
        }
        openIgnoreLine = nil
      default:
        if openIgnoreLine == nil {
          texts.append(lines[index].text)
        }
      }
    }
    if let openIgnoreLine {
      throw unbalancedIgnore(
        "ignore begin inside \(slug) has no matching ignore end before the span ends",
        lineIndex: openIgnoreLine,
        slug: slug,
      )
    }
    return texts
  }

  private func unbalancedIgnore(
    _ message: String,
    lineIndex: Int,
    slug: String,
  ) -> UnbalancedIgnore {
    UnbalancedIgnore(
      markerError: error(.marker(.unbalancedIgnore), message, lineIndex: lineIndex, slug: slug),
    )
  }

  /// A start with no explicit end. An explicit `begin` never gets an inferred
  /// end; a Swift file goes to the recognizer; anything else is unsupported.
  func resolveLoneStart(_ start: MarkerHit) -> BindingOutcome {
    let slug = start.slug
    let fix = "\"\(commentPrefix): @use-case:end \(slug)\""
    if start.explicitStart == true {
      return .error(error(
        .marker(.unsupportedInference),
        "explicit begin marker for \(slug) has no matching end; add \(fix)",
        lineIndex: start.lineIndex,
        slug: slug,
      ))
    }
    guard commentPrefix == "//", CommentPrefix.fileExtension(filePath) == ".swift" else {
      return .error(error(
        .marker(.unsupportedInference),
        "start marker for \(slug) has no explicit end; "
          + "inferred end is only supported for Swift func, requires explicit end",
        lineIndex: start.lineIndex,
        slug: slug,
      ))
    }
    return inferSwiftFunction(start, fix: fix)
  }

  private func inferSwiftFunction(
    _ start: MarkerHit,
    fix: String,
  ) -> BindingOutcome {
    let recognition = SwiftFunctionRecognizer.recognize(
      source: contents,
      markerLineIndex: start.lineIndex,
      markerCommentPrefix: commentPrefix,
    )
    switch recognition {
    case let .failed(code, message, _):
      return .error(error(
        .swiftFunction(code),
        "\(message); fix: add an explicit \(fix) or move the marker",
        lineIndex: start.lineIndex,
        slug: start.slug,
      ))
    case let .recognized(span, symbolName, bodyLines):
      return .binding(record(
        start: start,
        extentKind: .swiftFunctionInferred,
        endMarker: nil,
        span: BindingSpan(
          startLine: span.startLine,
          endLine: span.endLine,
          startByte: span.startByte,
          endByte: span.endByte,
          sha256: SpanCanonicalizer.hash(bodyLines),
        ),
        diagnostic: .inferredSwiftFunction(symbolName: symbolName),
      ))
    }
  }

  private func record(
    start: MarkerHit,
    extentKind: BindingExtentKind,
    endMarker: MarkerPosition?,
    span: BindingSpan,
    diagnostic: BindingDiagnostic,
  ) -> CurrentBindingRecord {
    let parts = MarkerSlug.split(start.slug)
    return CurrentBindingRecord(
      bindingSlug: start.slug,
      rowIdentifier: parts?.rowIdentifier ?? start.slug,
      suffix: parts?.suffix,
      filePath: filePath,
      commentPrefix: commentPrefix,
      extentKind: extentKind,
      recognizerIdentifier: extentKind == .explicit
        ? MarkerConstants.explicitRecognizerIdentifier
        : MarkerConstants.swiftFunctionRecognizerIdentifier,
      spanCanonicalizerIdentifier: MarkerConstants.spanCanonicalizerIdentifier,
      startMarker: MarkerPosition(line: start.lineIndex + 1, column: start.column),
      endMarker: endMarker,
      span: span,
      diagnostic: diagnostic,
    )
  }
}

/// An ignore region that does not balance inside its span.
struct UnbalancedIgnore: Error {
  let markerError: MarkerError
}
