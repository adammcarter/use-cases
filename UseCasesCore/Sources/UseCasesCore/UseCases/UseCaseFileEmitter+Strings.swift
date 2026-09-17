/// The scalar half of ``UseCaseFileEmitter``: `stringifyString` for the
/// default PLAIN type — plain when the core schema would read the text back as
/// the same string, otherwise quoted, or a literal block for multi-line text.
extension UseCaseFileEmitter {
  /// `stringifyString` with the default PLAIN type: double quotes when the text
  /// holds a control character, otherwise the plain-scalar rules decide.
  static func string(
    _ text: [UInt16],
    _ context: Context,
  ) -> [UInt16] {
    let hasControl = text.contains { unit in
      (0x00 ... 0x08).contains(unit) || (0x0B ... 0x1F).contains(unit) || (0x7F ... 0x9F)
        .contains(unit)
    }
    return hasControl ? DoubleQuotedScalar.text(text, context) : plain(text, context)
  }

  private static func plain(
    _ text: [UInt16],
    _ context: Context,
  ) -> [UInt16] {
    let hasLineFeed = text.contains(CodeUnits.lineFeed)
    if context.isImplicitKey, hasLineFeed {
      return quoted(text, context)
    }
    if PlainScalarRules.needsQuoting(text) {
      return context.isImplicitKey || !hasLineFeed ? quoted(text, context) : block(text, context)
    }
    if !context.isImplicitKey, hasLineFeed {
      return block(text, context)
    }
    if context.isImplicitKey, context.indent == indentStep,
       PlainScalarRules.startsWithDocumentMarker(text)
    {
      return quoted(text, context)
    }
    return PlainScalarRules.resolvesToNonString(text) ? quoted(text, context) : text
  }

  /// `quotedString`: single quotes only when the text has a `"` and no `'`.
  private static func quoted(
    _ text: [UInt16],
    _ context: Context,
  ) -> [UInt16] {
    let hasDouble = text.contains(CodeUnits.quotationMark)
    let hasSingle = text.contains(CodeUnits.apostrophe)
    return hasDouble && !hasSingle ? singleQuoted(text, context) : DoubleQuotedScalar.text(
      text,
      context,
    )
  }

  private static func singleQuoted(
    _ text: [UInt16],
    _ context: Context,
  ) -> [UInt16] {
    if context.isImplicitKey, text.contains(CodeUnits.lineFeed) {
      return DoubleQuotedScalar.text(text, context)
    }
    for index in text.indices.dropLast() {
      let pairStart = text[index]
      let pairEnd = text[index + 1]
      if (CodeUnits.isSpaceOrTab(pairStart) && pairEnd == CodeUnits.lineFeed)
        || (pairStart == CodeUnits.lineFeed && CodeUnits.isSpaceOrTab(pairEnd))
      {
        return DoubleQuotedScalar.text(text, context)
      }
    }
    var body: [UInt16] = []
    for unit in text {
      body += unit == CodeUnits.apostrophe ? [unit, unit] : [unit]
    }
    body = afterEachLineFeedRun(
      body,
      insert: [CodeUnits.lineFeed] + context.indent,
      onlyWhenFollowed: false,
    )
    return [CodeUnits.apostrophe] + body + [CodeUnits.apostrophe]
  }

  /// `blockString`, always literal (`lineWidth: 0` never folds): a `|` header
  /// with the chomping indicator the trailing whitespace needs, and `2` when the
  /// first line starts with a space.
  private static func block(
    _ text: [UInt16],
    _ context: Context,
  ) -> [UInt16] {
    if PlainScalarRules.endsWithIndentedEmptyLine(text) {
      return quoted(text, context)
    }
    let indent = context.indent
    let trailing = trailingWhitespace(of: text, indent: indent)
    let leading = leadingBlankLines(of: trailing.body, indent: indent)
    let header = (leading.startsWithSpace ? [0x32] : []) + trailing.chomp
    let body = afterEachLineFeedRun(leading.body, insert: indent, onlyWhenFollowed: false)
    return [CodeUnits.verticalLine] + header + [CodeUnits.lineFeed] + indent + leading.start + body
      + trailing.end
  }

  /// The trailing run of blanks and line feeds: the chomping indicator it asks
  /// for (`-` strip, `+` keep, none for clip), the text before it, and the run
  /// re-indented with its final line feed dropped.
  private static func trailingWhitespace(
    of text: [UInt16],
    indent: [UInt16],
  ) -> TrailingWhitespace {
    var endStart = text.count
    while endStart > 0,
          [CodeUnits.lineFeed, CodeUnits.tab, CodeUnits.space].contains(text[endStart - 1])
    {
      endStart -= 1
    }
    var end = Array(text[endStart...])
    let chomp: [UInt16] = if let lineFeed = end.firstIndex(of: CodeUnits.lineFeed) {
      endStart == 0 || lineFeed != end.count - 1 ? [CodeUnits.plusSign] : []
    } else {
      [CodeUnits.hyphenMinus]
    }
    if !end.isEmpty {
      if end.last == CodeUnits.lineFeed {
        end.removeLast()
      }
      end = afterEachLineFeedRun(end, insert: indent, onlyWhenFollowed: true)
    }
    return TrailingWhitespace(body: Array(text[..<endStart]), end: end, chomp: chomp)
  }

  /// The leading blank lines, up to and including the last line feed among the
  /// leading spaces and line feeds, re-indented; and whether a space came first.
  private static func leadingBlankLines(
    of text: [UInt16],
    indent: [UInt16],
  ) -> LeadingBlankLines {
    var startsWithSpace = false
    var lastLeadingLineFeed = -1
    for (position, unit) in text.enumerated() {
      if unit == CodeUnits.space {
        startsWithSpace = true
      } else if unit == CodeUnits.lineFeed {
        lastLeadingLineFeed = position
      } else {
        break
      }
    }
    let start = Array(text[..<(lastLeadingLineFeed + 1)])
    guard !start.isEmpty else {
      return LeadingBlankLines(start: start, body: text, startsWithSpace: startsWithSpace)
    }
    return LeadingBlankLines(
      start: afterEachLineFeedRun(start, insert: indent, onlyWhenFollowed: false),
      body: Array(text[start.count...]),
      startsWithSpace: startsWithSpace,
    )
  }

  /// `text.replace(/\n+/g, "$&" + insert)`. With `onlyWhenFollowed`, a run at
  /// the very end is left alone — `blockEndNewlines`' `(?!\n|$)`.
  static func afterEachLineFeedRun(
    _ text: [UInt16],
    insert: [UInt16],
    onlyWhenFollowed: Bool,
  ) -> [UInt16] {
    var output: [UInt16] = []
    var index = 0
    while index < text.count {
      output.append(text[index])
      if text[index] == CodeUnits.lineFeed,
         index + 1 == text.count || text[index + 1] != CodeUnits.lineFeed
      {
        if !onlyWhenFollowed || index + 1 < text.count {
          output += insert
        }
      }
      index += 1
    }
    return output
  }
}

/// A block scalar's trailing blanks: the text before them, the re-indented run,
/// and the chomping indicator it needs.
private struct TrailingWhitespace {
  let body: [UInt16]
  let end: [UInt16]
  let chomp: [UInt16]
}

/// A block scalar's leading blank lines, re-indented, the text after them, and
/// whether a space came first (which needs an indentation indicator).
private struct LeadingBlankLines {
  let start: [UInt16]
  let body: [UInt16]
  let startsWithSpace: Bool
}
