/// The Swift function recognizer for inferred-end markers (spec section 9).
///
/// A hand-written declaration recognizer, ported line for line from the
/// TypeScript rather than replaced with a real parser: the span it proves is
/// hashed into ledgers, so it must find the same span for the same source — and
/// fail closed in the same places. It never guesses.
///
/// It enforces the placement rule (9.2: the marker sits immediately above the
/// whole declaration group), computes the extent (9.3: first attribute or
/// modifier line through the body's closing brace, braces in strings and
/// comments ignored), and rejects every unsupported or ambiguous form (9.1, 9.4).
public enum SwiftFunctionRecognizer {
  public static func recognize(
    source: String,
    markerLineIndex: Int,
    markerCommentPrefix: String = "//",
  ) -> SwiftFunctionRecognition {
    let units = Array(source.utf16)
    let lines = PhysicalLines.split(codeUnits: units)
    do throws(RecognitionFailure) {
      let proof = try prove(
        units: units,
        lines: lines,
        markerLineIndex: markerLineIndex,
        markerCommentPrefix: markerCommentPrefix,
      )
      return .recognized(
        span: SwiftFunctionSpan(
          startLine: proof.startLineIndex + 1,
          endLine: proof.endLineIndex + 1,
          startByte: lines[proof.startLineIndex].byteStart,
          endByte: lines[proof.endLineIndex].byteEnd,
        ),
        symbolName: proof.symbolName,
        bodyLines: lines[proof.startLineIndex ... proof.endLineIndex].map(\.text),
      )
    } catch {
      return .failed(code: error.code, message: error.message, line: markerLineIndex + 1)
    }
  }

  private static func prove(
    units: [UInt16],
    lines: [PhysicalLine],
    markerLineIndex: Int,
    markerCommentPrefix: String,
  ) throws(RecognitionFailure) -> RecognitionProof {
    try checkPlacement(lines, markerLineIndex: markerLineIndex)
    let declarationLineIndex = markerLineIndex + 1
    try checkEnclosingConditional(lines, declarationLineIndex: declarationLineIndex)

    let mask = SwiftCodeMask(units)
    let tokens = SwiftCodeTokenizer.tokenize(
      units,
      mask: mask,
      from: lines[declarationLineIndex].codeUnitStart,
      to: units.count,
    )
    let headIndex = SwiftDeclarationHead.skipAttributesAndModifiers(tokens)
    let head = try SwiftDeclarationHead.requireFunction(tokens, at: headIndex)
    let symbolName = try SwiftDeclarationHead.symbolName(units, afterKeywordAt: head.position)

    guard SwiftScopeAnalysis.enclosingScopesAreAllTypes(units, mask: mask, until: head.position)
    else {
      throw RecognitionFailure(
        .nestedFunctionUnsupported,
        "func is nested inside a function/closure/non-type scope; "
          + "inferred mode supports only top-level and type-member funcs",
      )
    }

    let openPosition = try SwiftFunctionBody.openingBracePosition(tokens, after: headIndex)
    let closePosition = try SwiftFunctionBody.closingBracePosition(
      units,
      mask: mask,
      from: openPosition,
    )
    guard let endLineIndex = PhysicalLines.lineIndex(containingCodeUnit: closePosition, in: lines)
    else {
      throw RecognitionFailure(.swiftParseErrorInRegion, "could not locate the closing-brace line")
    }

    try checkSpanContents(
      lines[declarationLineIndex ... endLineIndex],
      markerCommentPrefix: markerCommentPrefix,
    )
    return RecognitionProof(
      startLineIndex: declarationLineIndex,
      endLineIndex: endLineIndex,
      symbolName: symbolName,
    )
  }

  /// Spec 9.2: the marker may not sit after an attached attribute or modifier,
  /// and the declaration group must begin on the very next line.
  private static func checkPlacement(
    _ lines: [PhysicalLine],
    markerLineIndex: Int,
  ) throws(RecognitionFailure) {
    guard markerLineIndex >= 0, markerLineIndex < lines.count else {
      throw RecognitionFailure(.markerNotAdjacentToDeclaration, "marker line is out of range")
    }
    if markerLineIndex > 0 {
      let above = Array(lines[markerLineIndex - 1].text.utf16)
      if !SwiftDeclarationGrammar.isBlank(above),
         SwiftDeclarationGrammar.startsAttachedDeclaration(above)
      {
        throw RecognitionFailure(
          .markerInsideAttachedDeclaration,
          "marker is placed after an attached attribute/modifier; "
            + "move it before the whole declaration group",
        )
      }
    }
    guard markerLineIndex + 1 < lines.count else {
      throw RecognitionFailure(
        .markerNotAdjacentToDeclaration,
        "marker has no declaration after it",
      )
    }
    let below = Array(lines[markerLineIndex + 1].text.utf16)
    if SwiftDeclarationGrammar.isBlank(below) {
      throw RecognitionFailure(
        .markerNotAdjacentToDeclaration,
        "blank line between marker and declaration",
      )
    }
    let belowTrimmed = SwiftDeclarationGrammar.trimmed(below)
    if belowTrimmed.starts(with: "//".utf16) || belowTrimmed.starts(with: "/*".utf16) {
      throw RecognitionFailure(
        .markerNotAdjacentToDeclaration,
        "comment between marker and declaration",
      )
    }
  }

  /// Spec 9.3 rule 8: an unbalanced `#if` open above the declaration.
  private static func checkEnclosingConditional(
    _ lines: [PhysicalLine],
    declarationLineIndex: Int,
  ) throws(RecognitionFailure) {
    var depth = 0
    for line in lines[..<declarationLineIndex] {
      let trimmed = SwiftDeclarationGrammar.trimmed(Array(line.text.utf16))
      if SwiftDeclarationGrammar.opensConditional(trimmed) {
        depth += 1
      } else if SwiftDeclarationGrammar.closesConditional(trimmed) {
        depth = max(0, depth - 1)
      }
    }
    if depth > 0 {
      throw RecognitionFailure(
        .conditionalCompilationInSpan,
        "declaration is inside a #if conditional-compilation block",
      )
    }
  }

  /// Spec 9.3 rules 9 then 8: no other marker, and no conditional-compilation
  /// directive, anywhere in the computed span.
  private static func checkSpanContents(
    _ span: ArraySlice<PhysicalLine>,
    markerCommentPrefix: String,
  ) throws(RecognitionFailure) {
    for (index, line) in zip(span.indices, span) {
      switch MarkerLineParser.parse(line.text, commentPrefix: markerCommentPrefix) {
      case .start, .end, .invalid:
        throw RecognitionFailure(
          .anotherMarkerInsideSpan,
          "another use-case marker appears inside the computed span (line \(index + 1))",
        )
      case .none, .ignoreBegin, .ignoreEnd:
        continue
      }
    }
    for (index, line) in zip(span.indices, span) {
      let trimmed = SwiftDeclarationGrammar.trimmed(Array(line.text.utf16))
      if SwiftDeclarationGrammar.isConditionalDirective(trimmed) {
        throw RecognitionFailure(
          .conditionalCompilationInSpan,
          "conditional-compilation directive inside the computed span (line \(index + 1))",
        )
      }
    }
  }
}

/// The line range and name a successful recognition proved.
private struct RecognitionProof {
  let startLineIndex: Int
  let endLineIndex: Int
  let symbolName: String
}

/// A 9.4 refusal on its way to becoming a ``SwiftFunctionRecognition/failed``.
struct RecognitionFailure: Error {
  let code: SwiftFunctionErrorCode
  let message: String

  init(
    _ code: SwiftFunctionErrorCode,
    _ message: String,
  ) {
    self.code = code
    self.message = message
  }
}
